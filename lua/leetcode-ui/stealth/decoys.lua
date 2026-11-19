---Uncalled work-style code shown as virtual lines around the solution in
---stealth mode. Keyed by language slug; languages without an entry get renames
---only.
---@type table<string, { above: string, below: string }>
return {
    python3 = {
        above = [[
from dataclasses import dataclass, field
import logging

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class AllocationRequest:
    order_id: str
    sku_codes: list[str] = field(default_factory=list)
    priority: int = 0


def _normalize_codes(codes: list[str]) -> list[str]:
    return sorted({code.strip().upper() for code in codes if code})

]],
        below = [[


def build_allocation_report(requests: list[AllocationRequest]) -> dict[str, int]:
    report: dict[str, int] = {}
    for request in requests:
        for code in _normalize_codes(request.sku_codes):
            report[code] = report.get(code, 0) + 1
    LOGGER.debug("Built allocation report codes=%d", len(report))
    return report]],
    },
}
