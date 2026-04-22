import sys
import os
import argparse

sys.path.insert(0, sys.path[0])

from notebook_executor import NotebookExecutor

def main():
    parser = argparse.ArgumentParser(description='Execute Post-Deployment Notebook')
    parser.add_argument('--workspace-id', required=True)
    parser.add_argument('--tenant-id', required=True)
    parser.add_argument('--client-id', required=True)
    parser.add_argument('--environment', required=True)
    parser.add_argument('--notebook-name', default='PostDeployment')
    args = parser.parse_args()

    print(f"Executing post-deployment notebook: {args.notebook_name}")
    print(f"   Environment: {args.environment}")
    print(f"   Workspace: {args.workspace_id}")

    client_secret = os.environ.get('CLIENT_SECRET')
    if not client_secret:
        print("Error: CLIENT_SECRET environment variable is not set.")
        sys.exit(1)

    executor = NotebookExecutor(
        workspace_id=args.workspace_id,
        tenant_id=args.tenant_id,
        client_id=args.client_id,
        client_secret=client_secret
    )

    result = executor.run_notebook_synchronous(
        notebook_name=args.notebook_name,
        timeout_seconds=1800
    )

    if result.get("status") == "Completed":
        print("Post-deployment notebook completed successfully.")
        sys.exit(0)
    else:
        print(f"Post-deployment notebook failed: {result.get('status')}")
        if "error" in result:
            print(f"   Error: {result['error']}")
        sys.exit(1)

if __name__ == "__main__":
    main()
