import azure.functions as func
import json
import logging

from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="shutdown_vm", methods=["POST", "GET"])
def shutdown_vm(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Shutdown VM request received.")

    req_body = {}
    try:
        req_body = req.get_json()
    except ValueError:
        req_body = {}

    if not isinstance(req_body, dict):
        req_body = {}

    subscription_id = req.params.get("subscription_id") or req_body.get("subscription_id")
    resource_group = req.params.get("resource_group") or req_body.get("resource_group")
    vm_name = req.params.get("vm_name") or req_body.get("vm_name")

    missing = [
        key
        for key, value in {
            "subscription_id": subscription_id,
            "resource_group": resource_group,
            "vm_name": vm_name,
        }.items()
        if not value
    ]
    if missing:
        payload = {
            "status": "error",
            "message": "Missing required parameters.",
            "missing": missing,
        }
        return func.HttpResponse(
            json.dumps(payload),
            status_code=400,
            mimetype="application/json",
        )

    try:
        credential = DefaultAzureCredential()
        client = ComputeManagementClient(credential, subscription_id)
        poller = client.virtual_machines.begin_deallocate(resource_group, vm_name)
    except Exception as exc:  # noqa: BLE001
        logging.exception("Failed to start VM deallocation.")
        payload = {
            "status": "error",
            "message": "Failed to start VM deallocation.",
            "details": str(exc),
        }
        return func.HttpResponse(
            json.dumps(payload),
            status_code=500,
            mimetype="application/json",
        )

    payload = {
        "status": "started",
        "operation": "deallocate",
        "subscription_id": subscription_id,
        "resource_group": resource_group,
        "vm_name": vm_name,
        "poller_status": poller.status(),
    }
    return func.HttpResponse(
        json.dumps(payload),
        status_code=202,
        mimetype="application/json",
    )