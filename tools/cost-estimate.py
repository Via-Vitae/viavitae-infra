#!/usr/bin/env python3
"""Estimate the monthly infrastructure cost for the current tenant count.

The numbers here are the inputs from docs/capacity-plan.md. If you change one,
change it there too.

Usage:
    python3 tools/cost-estimate.py --tenants 25
    python3 tools/cost-estimate.py --tenants 50 --quota-cpu 2 --quota-ram 4

The output is a table of cost centres with per-unit and total costs. The total
is the monthly cost of running the platform at the given tenant count, assuming
the hardware is amortised over 36 months.
"""
import argparse
import sys

# Hardware costs (monthly, EUR), amortised over 36 months.
# From capacity-plan.md §Hardware inventory.
HW = {
    "Proxmox nodes (2×)": 2 * 320,
    "NVMe for ZFS (4×)": 4 * 45,
    "mon-01 (monitoring)": 180,
    "backup-01 (backup storage)": 95,
    "Network (switches, UPS, rack)": 60,
    "Power (est. 1.2 kW × €0.12/kWh)": 130,
    "Colocation / DC": 200,
}

# Per-tenant variable costs (monthly, EUR).
# From capacity-plan.md §Growth assumptions.
PER_TENANT = {
    "Storage (2 GB initial + 150 MB/month × 36 = 7.4 GB avg)": 0.15,
    "WAL-G archive share (0.5 GB/day × 35 days × €0.02/GB)": 0.35,
    "Backup share (1.4× schema, 35-day WAL + 14-day vzdump)": 0.20,
    "Log volume (90 MB/day × 30 days × €0.01/GB)": 0.04,
    "Metric series (8 000 active × €0.001/series)": 8.00,
}

# Fixed monthly costs.
FIXED = {
    "Domain names (viavitae.com, viavitae.lt)": 2,
    "S3-compatible object store (base)": 15,
    "Monitoring licences (all AGPL/MIT/Apache — €0)": 0,
    "GitHub (self-hosted runners, no per-seat)": 0,
}


def estimate(tenants: int, quota_cpu: float, quota_ram: int) -> None:
    print(f"\nCost estimate for {tenants} tenants "
          f"(CPU quota: {quota_cpu}, RAM quota: {quota_ram} GiB)")
    print("=" * 72)

    # Hardware
    hw_total = sum(HW.values())
    print(f"\n{'Hardware (fixed, amortised 36 mo)':<45} {'€':>6}/mo")
    print("-" * 55)
    for name, cost in HW.items():
        print(f"  {name:<43} {cost:>6}")
    print(f"  {'':.<43} {'':.<6}")
    print(f"  {'Subtotal':.<43} {hw_total:>6}")

    # Per-tenant
    pt_unit = sum(PER_TENANT.values())
    pt_total = pt_unit * tenants
    print(f"\n{'Per-tenant variable costs':<45} {'€':>6}/mo")
    print("-" * 55)
    for name, cost in PER_TENANT.items():
        print(f"  {name:<43} {cost:>6.2f}")
    print(f"  {'':.<43} {'':.<6}")
    print(f"  {'Per-tenant subtotal':.<43} {pt_unit:>6.2f}")
    print(f"  {'× ' + str(tenants) + ' tenants':.<43} {pt_total:>6.2f}")

    # Fixed
    fixed_total = sum(FIXED.values())
    print(f"\n{'Fixed monthly costs':<45} {'€':>6}/mo")
    print("-" * 55)
    for name, cost in FIXED.items():
        print(f"  {name:<43} {cost:>6}")
    print(f"  {'':.<43} {'':.<6}")
    print(f"  {'Subtotal':.<43} {fixed_total:>6}")

    # Grand total
    grand = hw_total + pt_total + fixed_total
    print(f"\n{'=' * 55}")
    print(f"  {'GRAND TOTAL':.<43} {grand:>6.2f} €/mo")
    print(f"  {'Per-tenant at this count':.<43} {grand / max(tenants, 1):>6.2f} €/mo")
    print(f"{'=' * 55}")
    print()
    print("Notes:")
    print("  - Hardware costs are amortised over 36 months. The actual cash outflow")
    print("    is front-loaded; the per-month figure is for comparison with cloud.")
    print("  - Per-tenant costs assume the growth assumptions in capacity-plan.md.")
    print("  - The metric series cost (€8/tenant/month) is the largest variable cost.")
    print("    Reducing cardinality is the highest-leverage cost optimisation.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Estimate infrastructure cost.")
    parser.add_argument("--tenants", type=int, default=11,
                        help="Number of tenants (default: 11, current count)")
    parser.add_argument("--quota-cpu", type=float, default=2.0,
                        help="CPU quota per tenant in vCPU (default: 2)")
    parser.add_argument("--quota-ram", type=int, default=4,
                        help="RAM quota per tenant in GiB (default: 4)")
    args = parser.parse_args()

    if args.tenants < 1:
        print("ERROR: tenants must be >= 1", file=sys.stderr)
        sys.exit(1)

    estimate(args.tenants, args.quota_cpu, args.quota_ram)


if __name__ == "__main__":
    main()
