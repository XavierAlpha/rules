# Rules source directory

把 sing-box source-format 的无头规则 JSON 放在这里；支持任意子目录和任意数量文件。

示例：

```json
{
  "version": 1,
  "rules": [
    {
      "domain_suffix": ["example.com"]
    }
  ]
}
```

提交到仓库的 JSON 会在发布结果 `source/` 中原样保留。编译时只创建临时副本，并把临时副本的 `version` 设置为最新 stable sing-box 的 `RuleSetVersionCurrent`。

注意：最终 `.srs` 文件中的实际格式 version 由 sing-box 官方编译器根据规则所需字段决定，可能低于 `RuleSetVersionCurrent`。构建会读取 SRS 文件头并把实际 version 写入 `manifest.json`。
