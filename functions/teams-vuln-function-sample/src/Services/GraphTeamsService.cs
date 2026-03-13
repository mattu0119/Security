using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Microsoft.Extensions.Logging;
using TeamsVulnerabilityNotifier.Models;

namespace TeamsVulnerabilityNotifier.Services;

public sealed class GraphTeamsService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly HttpClient _httpClient;
    private readonly TokenCredential _credential;
    private readonly ILogger<GraphTeamsService> _logger;

    public GraphTeamsService(HttpClient httpClient, TokenCredential credential, ILogger<GraphTeamsService> logger)
    {
        _httpClient = httpClient;
        _credential = credential;
        _logger = logger;
    }

    public async Task<ChannelCreationResult> CreatePrivateChannelAndPostAsync(VulnerabilityNotificationRequest request, CancellationToken cancellationToken)
    {
        var teamId = string.IsNullOrWhiteSpace(request.TeamId)
            ? Environment.GetEnvironmentVariable("DEFAULT_TEAM_ID")
            : request.TeamId;

        if (string.IsNullOrWhiteSpace(teamId))
        {
            throw new InvalidOperationException("teamId is required. You can also configure DEFAULT_TEAM_ID in app settings.");
        }

        await AddGraphBearerTokenAsync(cancellationToken);

        var ownerIds = await ResolveUserIdsAsync(request.ChannelOwners, cancellationToken);
        var memberIds = await ResolveUserIdsAsync(request.ChannelMembers, cancellationToken);

        if (!ownerIds.Any())
        {
            throw new InvalidOperationException("At least one channel owner is required.");
        }

        var members = new List<Dictionary<string, object?>>();
        foreach (var ownerId in ownerIds.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            members.Add(BuildConversationMember(ownerId, isOwner: true));
        }

        foreach (var memberId in memberIds.Distinct(StringComparer.OrdinalIgnoreCase).Except(ownerIds, StringComparer.OrdinalIgnoreCase))
        {
            members.Add(BuildConversationMember(memberId, isOwner: false));
        }

        var channelPayload = new Dictionary<string, object?>
        {
            ["@odata.type"] = "#Microsoft.Graph.channel",
            ["membershipType"] = "private",
            ["displayName"] = request.ChannelDisplayName,
            ["description"] = request.ChannelDescription,
            ["members"] = members
        };

        var channelResponse = await PostAsync($"teams/{teamId}/channels", channelPayload, cancellationToken);
        using var channelJson = JsonDocument.Parse(channelResponse);
        var channelId = channelJson.RootElement.GetProperty("id").GetString() ?? throw new InvalidOperationException("Channel id was not returned by Graph.");
        var webUrl = channelJson.RootElement.TryGetProperty("webUrl", out var webUrlElement) ? webUrlElement.GetString() : null;

        var adaptiveCardJson = BuildAdaptiveCardJson(request);
        var messagePayload = new
        {
            body = new
            {
                contentType = "html",
                content = $"<p><strong>{WebUtility.HtmlEncode(request.Title ?? "Vulnerability notification")}</strong></p><p>{WebUtility.HtmlEncode(request.Summary ?? string.Empty)}</p>"
            },
            attachments = new[]
            {
                new
                {
                    id = Guid.NewGuid().ToString("N"),
                    contentType = "application/vnd.microsoft.card.adaptive",
                    contentUrl = (string?)null,
                    content = adaptiveCardJson
                }
            }
        };

        var messageResponse = await PostAsync($"teams/{teamId}/channels/{channelId}/messages", messagePayload, cancellationToken);
        using var messageJson = JsonDocument.Parse(messageResponse);
        var messageId = messageJson.RootElement.GetProperty("id").GetString();

        return new ChannelCreationResult(channelId, messageId, webUrl);
    }

    private static Dictionary<string, object?> BuildConversationMember(string userId, bool isOwner)
    {
        return new Dictionary<string, object?>
        {
            ["@odata.type"] = "#microsoft.graph.aadUserConversationMember",
            ["roles"] = isOwner ? new[] { "owner" } : Array.Empty<string>(),
            ["user@odata.bind"] = $"https://graph.microsoft.com/v1.0/users('{userId}')"
        };
    }

    private async Task AddGraphBearerTokenAsync(CancellationToken cancellationToken)
    {
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }),
            cancellationToken);

        _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
    }

    private async Task<List<string>> ResolveUserIdsAsync(IEnumerable<UserReference> users, CancellationToken cancellationToken)
    {
        var results = new List<string>();

        foreach (var user in users.Where(u => !string.IsNullOrWhiteSpace(u.Upn)))
        {
            var escaped = Uri.EscapeDataString(user.Upn!);
            var json = await GetAsync($"users/{escaped}?$select=id,userPrincipalName", cancellationToken);
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("id", out var idProp))
            {
                var id = idProp.GetString();
                if (!string.IsNullOrWhiteSpace(id))
                {
                    results.Add(id);
                }
            }
        }

        return results;
    }

    private async Task<string> GetAsync(string relativeUrl, CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(relativeUrl, cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Graph GET failed. Url: {Url}, Status: {Status}, Body: {Body}", relativeUrl, response.StatusCode, content);
            throw new HttpRequestException($"Graph GET failed: {response.StatusCode}. {content}");
        }

        return content;
    }

    private async Task<string> PostAsync(string relativeUrl, object payload, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(payload, JsonOptions);
        using var request = new HttpRequestMessage(HttpMethod.Post, relativeUrl)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("Graph POST failed. Url: {Url}, Status: {Status}, Body: {Body}", relativeUrl, response.StatusCode, content);
            throw new HttpRequestException($"Graph POST failed: {response.StatusCode}. {content}");
        }

        return content;
    }

    private static string BuildAdaptiveCardJson(VulnerabilityNotificationRequest request)
    {
        var facts = new List<object>
        {
            new { title = "Event ID", value = request.EventId ?? string.Empty },
            new { title = "Vulnerability ID", value = request.VulnerabilityId ?? string.Empty },
            new { title = "Severity", value = request.Severity ?? string.Empty },
            new { title = "CVSS", value = request.CvssScore?.ToString() ?? string.Empty },
            new { title = "Product", value = request.AffectedProduct ?? string.Empty },
            new { title = "Version", value = request.AffectedVersion ?? string.Empty },
            new { title = "Detected At", value = request.DetectedAt?.ToString("u") ?? string.Empty },
            new { title = "Due Date", value = request.DueDate?.ToString("u") ?? string.Empty },
            new { title = "Source", value = request.SourceSystem ?? string.Empty }
        };

        var body = new List<object>
        {
            new { type = "TextBlock", text = request.Title ?? "Vulnerability notification", size = "Large", weight = "Bolder", wrap = true },
            new { type = "TextBlock", text = request.Summary ?? string.Empty, wrap = true, spacing = "Medium" },
            new { type = "FactSet", facts },
            new { type = "TextBlock", text = $"Remediation: {request.Remediation}", wrap = true, spacing = "Medium" }
        };

        if (request.ReferenceUrls.Any())
        {
            body.Add(new { type = "TextBlock", text = "Reference URLs", weight = "Bolder", spacing = "Medium" });
            foreach (var link in request.ReferenceUrls.Where(x => !string.IsNullOrWhiteSpace(x.Url)))
            {
                body.Add(new { type = "TextBlock", text = $"[{link.Label ?? link.Url}]({link.Url})", wrap = true });
            }
        }

        var card = new
        {
            type = "AdaptiveCard",
            $schema = "http://adaptivecards.io/schemas/adaptive-card.json",
            version = "1.5",
            body,
            actions = new object[]
            {
                new { type = "Action.OpenUrl", title = "Reference", url = request.ReferenceUrls.FirstOrDefault(x => !string.IsNullOrWhiteSpace(x.Url))?.Url ?? "https://portal.azure.com" },
                new { type = "Action.Submit", title = "対応済み", data = new { action = "mitigated", eventId = request.EventId, vulnerabilityId = request.VulnerabilityId, correlationId = request.CorrelationId } }
            }
        };

        return JsonSerializer.Serialize(card, JsonOptions);
    }
}

public readonly record struct ChannelCreationResult(string ChannelId, string? MessageId, string? WebUrl);
