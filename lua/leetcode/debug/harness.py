"""Run a LeetCode Python solution locally on the testcase pane's inputs.

Started by leetcode.nvim under debugpy. The solution file is compiled with its
real path, so breakpoints set in the editor are hit.
"""

import json
import sys
from collections import deque
from pathlib import Path
from typing import Any


class ListNode:
    def __init__(self, val=0, next=None):
        self.val = val
        self.next = next

    def __repr__(self):
        return f"ListNode({_list_to_values(self)})"


class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right

    def __repr__(self):
        return f"TreeNode({_tree_to_values(self)})"


def _build_list(values: list | None) -> ListNode | None:
    head = None
    for value in reversed(values or []):
        head = ListNode(value, head)
    return head


def _list_to_values(node: ListNode | None) -> list:
    values, seen = [], set()
    while node is not None and id(node) not in seen:
        seen.add(id(node))
        values.append(node.val)
        node = node.next
    return values


def _build_tree(values: list | None) -> TreeNode | None:
    if not values or values[0] is None:
        return None
    root = TreeNode(values[0])
    queue, i = deque([root]), 1
    while queue and i < len(values):
        node = queue.popleft()
        for side in ("left", "right"):
            if i < len(values) and values[i] is not None:
                child = TreeNode(values[i])
                setattr(node, side, child)
                queue.append(child)
            i += 1
    return root


def _tree_to_values(root: TreeNode | None) -> list:
    values, queue = [], deque([root])
    while queue:
        node = queue.popleft()
        values.append(None if node is None else node.val)
        if node is not None:
            queue.extend((node.left, node.right))
    while values and values[-1] is None:
        values.pop()
    return values


def _convert(value: Any, type_name: str) -> Any:
    if type_name == "ListNode":
        return _build_list(value)
    if type_name == "TreeNode":
        return _build_tree(value)
    if type_name == "ListNode[]":
        return [_build_list(v) for v in value]
    return value


def _show(value: Any) -> str:
    if isinstance(value, ListNode):
        return json.dumps(_list_to_values(value))
    if isinstance(value, TreeNode):
        return json.dumps(_tree_to_values(value))
    if isinstance(value, list) and value and isinstance(value[0], ListNode):
        return json.dumps([_list_to_values(v) for v in value])
    try:
        return json.dumps(value)
    except TypeError:
        return repr(value)


def _run_function(namespace: dict, meta: dict, case: list[str]) -> None:
    params = meta["params"]
    args = [_convert(json.loads(line), p["type"]) for line, p in zip(case, params)]
    method = getattr(namespace["Solution"](), meta["name"])
    print("Input:  " + ", ".join(f"{p['name']} = {line}" for line, p in zip(case, params)))
    result = method(*args)
    if meta.get("return", {}).get("type") == "void" and args:
        result = args[0]
    print("Output: " + _show(result))


def _run_design(namespace: dict, meta: dict, case: list[str]) -> None:
    calls, arguments = json.loads(case[0]), json.loads(case[1])
    methods = {m["name"]: m for m in meta.get("methods", [])}
    constructor_params = meta.get("constructor", {}).get("params", [])
    outputs, instance = [], None
    for name, args in zip(calls, arguments):
        if instance is None:
            converted = [_convert(a, p["type"]) for a, p in zip(args, constructor_params)]
            instance = namespace[meta["classname"]](*converted)
            outputs.append(None)
            continue
        params = methods.get(name, {}).get("params", [])
        converted = [_convert(a, p["type"]) for a, p in zip(args, params)]
        outputs.append(getattr(instance, name)(*converted))
    print("Input:  " + case[0])
    print("Output: " + _show(outputs))


def main() -> None:
    spec = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    sys.setrecursionlimit(100_000)

    solution = Path(spec["solution"])
    namespace = {"__name__": "solution", "ListNode": ListNode, "TreeNode": TreeNode}
    exec(compile(solution.read_text(encoding="utf-8"), str(solution), "exec"), namespace)

    meta = spec["meta"]
    run = _run_design if meta.get("systemdesign") else _run_function
    for number, case in enumerate(spec["cases"], start=1):
        print(f"Case {number}")
        run(namespace, meta, case)
        print()


if __name__ == "__main__":
    main()
