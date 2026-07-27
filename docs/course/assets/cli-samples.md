# CLI 输出样例（教学用）

## usage-watch --once（完整视图）
```
Usage windows  |  7/28/2026, 1:31:59 AM

Codex   | Pro
  7d  [████░░░░░░░░]  left   34%  ↻ Aug 2, 07:01 AM  (  5d 5h)

Claude  | Max 20×
  5h  [████████████]  left   97%  ↻ Jul 28, 06:20 AM ( 4h 48m)
  7d  [████████████]  left   97%  ↻ Aug 2, 10:59 PM  ( 5d 21h)
```

## usage-watch --line（单行，适合状态栏）
```
Codex  ‖  Claude 5h 97% 7d 97%
```

## usage-watch --json（供 HUD 的表盘皮肤解析）
```json
{
    "fetchedAt": 1785173521079,
    "providers": [
        {
            "name": "Codex",
            "plan": "pro",
            "planLabel": "Pro",
            "staleSec": null,
            "windows": [
                {
                    "label": "7d",
                    "leftPercent": 34,
                    "resetsAt": 1785625266,
                    "windowMinutes": 10080
                }
            ]
        },
        {
            "name": "Claude",
            "plan": "max",
            "tier": "default_claude_max_20x",
            "planLabel": "Max 20\u00d7",
            "staleSec": null,
            "windows": [
                {
                    "label": "5h",
                    "leftPercent": 97,
                    "resetsAt": 1785190800.648,
                    "windowMinutes": 300
                },
                {
                    "label": "7d",
                    "leftPercent": 97,
                    "resetsAt": 1785682799.648,
                    "windowMinutes": 10080
                }
            ]
        }
    ]
}
```
