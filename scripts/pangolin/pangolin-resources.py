#!/usr/bin/env python3
"""
Pangolin Public Resources Management Script

Manages public HTTPS resources in Pangolin for homelab services.
Creates resources with subdomains that are publicly accessible via Pangolin's
reverse proxy and automatic TLS.

Usage:
    python3 pangolin-resources.py --config /path/to/config.yaml --resources /path/to/resources.yaml list
    python3 pangolin-resources.py --config /path/to/config.yaml --resources /path/to/resources.yaml sync --dry-run
    python3 pangolin-resources.py --config /path/to/config.yaml --resources /path/to/resources.yaml sync

API key is loaded from SOPS-encrypted pangolin-creds.enc.yaml (next to config.yaml).
Override with PANGOLIN_API_KEY env var or --token-file argument.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


class PangolinClient:
    """Client for Pangolin Integration API (public resources)."""

    def __init__(self, api_key: str, base_url: str):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.max_retries = 3
        self.retry_delay = 2

    def _request(
        self, method: str, endpoint: str, data: dict | None = None
    ) -> dict:
        """Make an API request with retry logic."""
        url = f"{self.base_url}/v1{endpoint}"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Accept": "application/json",
        }

        body = None
        if data is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(data).encode()

        for attempt in range(self.max_retries):
            try:
                req = urllib.request.Request(
                    url, data=body, headers=headers, method=method
                )
                with urllib.request.urlopen(req, timeout=30) as response:
                    response_body = response.read().decode()
                    if not response_body:
                        return {}
                    return json.loads(response_body)
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    wait = self.retry_delay * (attempt + 1)
                    print(f"  Rate limited, waiting {wait}s...")
                    time.sleep(wait)
                    continue
                error_body = e.read().decode() if e.fp else ""
                raise RuntimeError(
                    f"API error {e.code} on {method} {endpoint}: {error_body}"
                ) from e
            except urllib.error.URLError as e:
                if attempt < self.max_retries - 1:
                    time.sleep(self.retry_delay)
                    continue
                raise RuntimeError(f"Network error: {e.reason}") from e

        raise RuntimeError("Max retries exceeded")

    # -- Public resource endpoints --

    def list_resources(self, org_id: str) -> list[dict]:
        """List all public resources for an organization."""
        resp = self._request("GET", f"/org/{org_id}/resources")
        return resp.get("data", {}).get("resources", [])

    def create_resource(
        self,
        org_id: str,
        name: str,
        subdomain: str,
        domain_id: str,
    ) -> dict:
        """Create a public HTTPS resource.

        Returns the full API response including resourceId and fullDomain.
        """
        data = {
            "name": name,
            "http": True,
            "domainId": domain_id,
            "protocol": "tcp",
            "subdomain": subdomain,
        }
        return self._request("PUT", f"/org/{org_id}/resource", data)

    def add_target(
        self,
        resource_id: str,
        site_id: int,
        ip: str,
        port: int,
        method: str = "http",
    ) -> dict:
        """Add a target (backend) to a resource."""
        data = {
            "siteId": site_id,
            "ip": ip,
            "port": port,
            "method": method,
        }
        return self._request("PUT", f"/resource/{resource_id}/target", data)

    def delete_resource(self, resource_id: str) -> dict:
        """Delete a public resource."""
        return self._request("DELETE", f"/resource/{resource_id}")


def load_token_from_sops(token_file: Path) -> str | None:
    """Load API key from SOPS-encrypted file."""
    if not token_file.exists():
        return None

    try:
        result = subprocess.run(
            ["sops", "-d", str(token_file)],
            capture_output=True,
            text=True,
            check=True,
        )
        data = yaml.safe_load(result.stdout)
        return data.get("pangolin_api_key")
    except subprocess.CalledProcessError as e:
        print(f"Error decrypting token file: {e.stderr}")
        return None
    except FileNotFoundError:
        print(
            "Error: 'sops' command not found. "
            "Install SOPS or set PANGOLIN_API_KEY env var."
        )
        return None


def load_config(config_path: Path) -> dict:
    """Load configuration from YAML file."""
    with open(config_path) as f:
        return yaml.safe_load(f)


def load_resources(resources_path: Path) -> list[dict]:
    """Load resource definitions from YAML file."""
    with open(resources_path) as f:
        data = yaml.safe_load(f)
        return data.get("resources", [])


def build_desired_state(
    resources: list[dict], config: dict
) -> dict[str, dict]:
    """Build desired state from resource definitions.

    Returns a dict mapping resource name to its desired config.
    The key is the subdomain since that uniquely identifies a public resource.
    """
    base_domain = config.get("base_domain", "")
    desired = {}

    for resource in resources:
        name = resource["name"]
        subdomain = resource["subdomain"]
        full_domain = f"{subdomain}.{base_domain}" if base_domain else subdomain

        desired[subdomain] = {
            "name": name,
            "subdomain": subdomain,
            "full_domain": full_domain,
            "target_ip": resource["target_ip"],
            "target_port": resource.get("target_port", 80),
        }

    return desired


def parse_current_state(resources: list[dict], base_domain: str = "") -> dict[str, dict]:
    """Parse current API resources into subdomain -> config mapping."""
    current = {}
    for resource in resources:
        name = resource.get("name", "")
        full_domain = resource.get("fullDomain", "")
        # API may return subdomain as null — extract from fullDomain
        subdomain = resource.get("subdomain") or ""
        if not subdomain and full_domain and base_domain:
            suffix = f".{base_domain}"
            if full_domain.endswith(suffix):
                subdomain = full_domain[: -len(suffix)]

        current[subdomain] = {
            "resource_id": resource.get("resourceId"),
            "name": name,
            "subdomain": subdomain,
            "full_domain": full_domain,
        }
    return current


def cmd_list(client: PangolinClient, config: dict) -> int:
    """List current public resources in Pangolin."""
    org_id = config["org_id"]
    print(f"Organization: {org_id}")

    print("\nFetching public resources...")
    resources = client.list_resources(org_id)

    if not resources:
        print("No public resources found.")
        return 0

    print(f"\nPublic resources ({len(resources)} total):")
    print("-" * 80)

    for resource in sorted(resources, key=lambda r: r.get("name", "")):
        name = resource.get("name", "unknown")
        full_domain = resource.get("fullDomain", "")
        resource_id = resource.get("resourceId", "?")
        print(f"  {name:<25} {full_domain:<40} (ID: {resource_id})")

    return 0


def cmd_sync(
    client: PangolinClient,
    config: dict,
    resources: list[dict],
    dry_run: bool = False,
) -> int:
    """Sync desired resources with Pangolin.

    Idempotent: compares desired vs current state, only creates/deletes
    what is needed. Matches resources by name.
    """
    org_id = config["org_id"]
    site_id = int(config["site_id"])
    domain_id = config["domain_id"]
    print(f"Organization: {org_id}")
    print(f"Site ID: {site_id}")
    print(f"Domain ID: {domain_id}")

    # Build desired state
    desired = build_desired_state(resources, config)
    print(f"\nDesired state: {len(desired)} resources")

    # Get current state
    print("Fetching current resources...")
    current_resources = client.list_resources(org_id)
    current = parse_current_state(current_resources, config.get("base_domain", ""))
    print(f"Current state: {len(current)} resources")

    # Calculate changes
    to_create = set(desired.keys()) - set(current.keys())
    to_delete = set(current.keys()) - set(desired.keys())
    unchanged = set(desired.keys()) & set(current.keys())

    # Check for subdomain changes on existing resources (requires recreate)
    to_recreate = set()
    for name in unchanged:
        if desired[name]["subdomain"] != current[name]["subdomain"]:
            to_recreate.add(name)

    # Report
    print(f"\n{'Sync preview (dry-run)' if dry_run else 'Sync changes'}:")
    print("-" * 80)

    if not to_create and not to_delete and not to_recreate:
        print("No changes needed - already in sync!")
        return 0

    for key in sorted(to_create):
        d = desired[key]
        print(
            f"  [CREATE] {d['name']:<25} -> {d['full_domain']:<35} "
            f"({d['target_ip']}:{d['target_port']})"
        )

    for key in sorted(to_recreate):
        d = desired[key]
        c = current[key]
        print(
            f"  [RECREATE] {d['name']:<23} {c['subdomain']} -> {d['subdomain']}"
        )

    for key in sorted(to_delete):
        c = current[key]
        print(f"  [DELETE] {c['name']:<25} ({c['full_domain']})")

    total_creates = len(to_create) + len(to_recreate)
    total_deletes = len(to_delete) + len(to_recreate)
    print(
        f"\nWould create: {total_creates}, "
        f"delete: {total_deletes}, "
        f"unchanged: {len(unchanged) - len(to_recreate)}"
    )

    if dry_run:
        print("\nDry-run mode - no changes applied.")
        return 0

    # Apply changes
    print("\nApplying changes...")
    errors = 0

    # Delete resources that are no longer desired (and those being recreated)
    for key in sorted(to_delete | to_recreate):
        try:
            resource_id = current[key]["resource_id"]
            print(f"  Deleting {current[key]['name']}...", end=" ")
            client.delete_resource(resource_id)
            print("OK")
        except Exception as e:
            print(f"FAILED: {e}")
            errors += 1

    # Create new resources (and recreated ones)
    for key in sorted(to_create | to_recreate):
        try:
            d = desired[key]
            print(
                f"  Creating {d['name']} ({d['full_domain']})...",
                end=" ",
            )

            # Step 1: Create the resource
            resp = client.create_resource(
                org_id=org_id,
                name=d["name"],
                subdomain=d["subdomain"],
                domain_id=domain_id,
            )

            resource_id = resp.get("data", {}).get("resourceId")
            if not resource_id:
                print(f"FAILED: No resourceId in response: {resp}")
                errors += 1
                continue

            print(f"ID={resource_id}", end=" ")

            # Step 2: Add the target
            print("-> adding target...", end=" ")
            client.add_target(
                resource_id=resource_id,
                site_id=site_id,
                ip=d["target_ip"],
                port=d["target_port"],
            )
            print("OK")

        except Exception as e:
            print(f"FAILED: {e}")
            errors += 1

    if errors:
        print(f"\nCompleted with {errors} error(s)")
        return 1

    print("\nSync completed successfully!")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Manage Pangolin public HTTPS resources for homelab services"
    )
    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help="Path to config.yaml (environment-specific)",
    )
    parser.add_argument(
        "--resources",
        type=Path,
        required=True,
        help="Path to resources.yaml (environment-specific)",
    )
    parser.add_argument(
        "--token-file",
        type=Path,
        default=None,
        help=(
            "Path to SOPS-encrypted credentials file "
            "(default: pangolin-creds.enc.yaml next to config.yaml)"
        ),
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # list command
    subparsers.add_parser("list", help="List current public resources")

    # sync command
    sync_parser = subparsers.add_parser(
        "sync", help="Sync desired resources with Pangolin"
    )
    sync_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without applying",
    )

    args = parser.parse_args()

    # Resolve token file path
    token_file = args.token_file
    if token_file is None:
        token_file = args.config.parent / "pangolin-creds.enc.yaml"

    # Get API key: env var takes precedence, then SOPS file
    api_key = os.environ.get("PANGOLIN_API_KEY")
    if not api_key:
        if token_file.exists():
            print(f"Loading API key from {token_file}...")
            api_key = load_token_from_sops(token_file)

    if not api_key:
        print("Error: No API key found")
        print("Options:")
        print(
            f"  1. Add pangolin_api_key to SOPS-encrypted file: {token_file}"
        )
        print("  2. Set PANGOLIN_API_KEY environment variable")
        print("  3. Use --token-file to specify a different file")
        sys.exit(1)

    # Load config
    if not args.config.exists():
        print(f"Error: Config file not found: {args.config}")
        sys.exit(1)

    config = load_config(args.config)
    client = PangolinClient(
        api_key, config.get("pangolin_url", "https://api.home-infra.net")
    )

    # Execute command
    if args.command == "list":
        sys.exit(cmd_list(client, config))
    elif args.command == "sync":
        if not args.resources.exists():
            print(f"Error: Resources file not found: {args.resources}")
            sys.exit(1)
        resources_list = load_resources(args.resources)
        sys.exit(cmd_sync(client, config, resources_list, args.dry_run))


if __name__ == "__main__":
    main()
