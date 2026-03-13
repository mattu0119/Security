using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using TeamsVulnerabilityNotifier.Services;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddSingleton<TokenCredential>(_ => new DefaultAzureCredential());
        services.AddHttpClient<GraphTeamsService>(client =>
        {
            var graphBaseUrl = Environment.GetEnvironmentVariable("GRAPH_BASE_URL") ?? "https://graph.microsoft.com/v1.0";
            client.BaseAddress = new Uri(graphBaseUrl.TrimEnd('/') + "/");
            client.Timeout = TimeSpan.FromSeconds(100);
        });
    })
    .Build();

host.Run();
