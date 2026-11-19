---Uncalled work-style code shown as virtual lines around the solution in
---stealth mode, so the file reads like part of a codebase. Keyed by language
---slug; languages without an entry get the rename only.
---@type table<string, { above: string, below: string }>
local decoys = {}

decoys.python3 = {
    above = [=[
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone

LOGGER = logging.getLogger(__name__)

DEFAULT_BATCH_SIZE = 500


@dataclass(frozen=True)
class AllocationRequest:
    order_id: str
    sku_codes: list[str] = field(default_factory=list)
    priority: int = 0
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


def _normalize_codes(codes: list[str]) -> list[str]:
    return sorted({code.strip().upper() for code in codes if code})


def _chunk(items: list[str], size: int = DEFAULT_BATCH_SIZE) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]

]=],
    below = [=[


def build_allocation_report(requests: list[AllocationRequest]) -> dict[str, int]:
    report: dict[str, int] = {}
    for request in sorted(requests, key=lambda r: (-r.priority, r.created_at)):
        for code in _normalize_codes(request.sku_codes):
            report[code] = report.get(code, 0) + 1
    LOGGER.debug("Built allocation report codes=%d", len(report))
    return report


def pending_batches(requests: list[AllocationRequest]) -> list[list[str]]:
    codes = [code for request in requests for code in _normalize_codes(request.sku_codes)]
    return _chunk(codes)]=],
}
decoys.python = decoys.python3

decoys.cpp = {
    above = [=[
#include <algorithm>
#include <string>
#include <unordered_map>
#include <vector>

namespace inventory {

struct AllocationRequest {
    std::string order_id;
    std::vector<std::string> sku_codes;
    int priority = 0;
};

static std::string normalize(const std::string& code) {
    std::string out = code;
    std::transform(out.begin(), out.end(), out.begin(), ::toupper);
    return out;
}

}  // namespace inventory
]=],
    below = [=[

namespace inventory {

std::unordered_map<std::string, int> build_report(const std::vector<AllocationRequest>& requests) {
    std::unordered_map<std::string, int> report;
    for (const auto& request : requests) {
        for (const auto& code : request.sku_codes) {
            ++report[normalize(code)];
        }
    }
    return report;
}

}  // namespace inventory]=],
}

decoys.c = {
    above = [=[
#include <stdlib.h>
#include <string.h>

#define MAX_CODES 64

typedef struct {
    char order_id[32];
    char sku_codes[MAX_CODES][16];
    int code_count;
    int priority;
} allocation_request;

static int compare_priority(const void *a, const void *b) {
    const allocation_request *x = a, *y = b;
    return y->priority - x->priority;
}
]=],
    below = [=[

void sort_requests(allocation_request *requests, size_t count) {
    qsort(requests, count, sizeof(*requests), compare_priority);
}]=],
}

decoys.java = {
    above = [=[
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record AllocationRequest(String orderId, List<String> skuCodes, int priority) {}

final class Codes {
    private Codes() {}

    static String normalize(String code) {
        return code.trim().toUpperCase();
    }
}
]=],
    below = [=[

final class AllocationReport {
    private final Map<String, Integer> counts = new HashMap<>();

    void add(AllocationRequest request) {
        for (String code : request.skuCodes()) {
            counts.merge(Codes.normalize(code), 1, Integer::sum);
        }
    }

    List<String> codes() {
        return new ArrayList<>(counts.keySet());
    }
}]=],
}

decoys.csharp = {
    above = [=[
using System.Collections.Generic;
using System.Linq;

public record AllocationRequest(string OrderId, IReadOnlyList<string> SkuCodes, int Priority);

internal static class Codes
{
    public static string Normalize(string code) => code.Trim().ToUpperInvariant();
}
]=],
    below = [=[

public sealed class AllocationReport
{
    private readonly Dictionary<string, int> _counts = new();

    public void Add(AllocationRequest request)
    {
        foreach (var code in request.SkuCodes.Select(Codes.Normalize))
        {
            _counts[code] = _counts.GetValueOrDefault(code) + 1;
        }
    }
}]=],
}

decoys.javascript = {
    above = [=[
const DEFAULT_BATCH_SIZE = 500;

/**
 * @param {string[]} codes
 * @returns {string[]}
 */
function normalizeCodes(codes) {
  return [...new Set(codes.filter(Boolean).map((code) => code.trim().toUpperCase()))].sort();
}

function chunk(items, size = DEFAULT_BATCH_SIZE) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
]=],
    below = [=[

function buildAllocationReport(requests) {
  const report = new Map();
  for (const request of requests) {
    for (const code of normalizeCodes(request.skuCodes)) {
      report.set(code, (report.get(code) ?? 0) + 1);
    }
  }
  return report;
}

module.exports = { buildAllocationReport, chunk };]=],
}

decoys.typescript = {
    above = [=[
export interface AllocationRequest {
  orderId: string;
  skuCodes: string[];
  priority: number;
}

const DEFAULT_BATCH_SIZE = 500;

function normalizeCodes(codes: string[]): string[] {
  return [...new Set(codes.filter(Boolean).map((code) => code.trim().toUpperCase()))].sort();
}
]=],
    below = [=[

export function buildAllocationReport(requests: AllocationRequest[]): Map<string, number> {
  const report = new Map<string, number>();
  for (const request of requests) {
    for (const code of normalizeCodes(request.skuCodes)) {
      report.set(code, (report.get(code) ?? 0) + 1);
    }
  }
  return report;
}]=],
}

decoys.golang = {
    above = [=[
package inventory

import (
	"sort"
	"strings"
)

type AllocationRequest struct {
	OrderID  string
	SkuCodes []string
	Priority int
}

func normalize(codes []string) []string {
	out := make([]string, 0, len(codes))
	for _, code := range codes {
		out = append(out, strings.ToUpper(strings.TrimSpace(code)))
	}
	sort.Strings(out)
	return out
}
]=],
    below = [=[

func BuildReport(requests []AllocationRequest) map[string]int {
	report := make(map[string]int)
	for _, request := range requests {
		for _, code := range normalize(request.SkuCodes) {
			report[code]++
		}
	}
	return report
}]=],
}

decoys.rust = {
    above = [=[
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct AllocationRequest {
    pub order_id: String,
    pub sku_codes: Vec<String>,
    pub priority: i32,
}

fn normalize(code: &str) -> String {
    code.trim().to_uppercase()
}
]=],
    below = [=[

pub fn build_report(requests: &[AllocationRequest]) -> HashMap<String, usize> {
    let mut report = HashMap::new();
    for request in requests {
        for code in &request.sku_codes {
            *report.entry(normalize(code)).or_insert(0) += 1;
        }
    }
    report
}]=],
}

decoys.kotlin = {
    above = [=[
data class AllocationRequest(
    val orderId: String,
    val skuCodes: List<String>,
    val priority: Int = 0,
)

private fun normalize(code: String): String = code.trim().uppercase()
]=],
    below = [=[

fun buildReport(requests: List<AllocationRequest>): Map<String, Int> =
    requests
        .flatMap { it.skuCodes }
        .map(::normalize)
        .groupingBy { it }
        .eachCount()]=],
}

decoys.swift = {
    above = [=[
import Foundation

struct AllocationRequest {
    let orderId: String
    let skuCodes: [String]
    var priority = 0
}

private func normalize(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespaces).uppercased()
}
]=],
    below = [=[

func buildReport(_ requests: [AllocationRequest]) -> [String: Int] {
    var report: [String: Int] = [:]
    for request in requests {
        for code in request.skuCodes.map(normalize) {
            report[code, default: 0] += 1
        }
    }
    return report
}]=],
}

return decoys
