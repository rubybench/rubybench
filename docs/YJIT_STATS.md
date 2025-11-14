# YJIT Stats Collection for Rubybench

## Overview

This feature adds YJIT runtime statistics collection to rubybench, similar to what's available in the yjit-metrics repository. It collects detailed JIT compilation metrics and generates exit reports showing why YJIT exits to the interpreter.

## Features

- **YJIT Stats Collection**: Collects ~45 essential metrics from `RubyVM::YJIT.runtime_stats`
- **Exit Reports**: Detailed text reports showing exit reasons and compilation statistics
- **Stats Dashboard**: HTML dashboard displaying key metrics for all benchmarks
- **Optimized Storage**: Uses a hybrid approach storing essential metrics + exit reports (~113 MB/year vs 365 MB for full data)

## Architecture

### Data Storage Structure

```
results/
├── ruby-bench/              # Existing execution times
│   └── activerecord.yml
├── yjit-stats/              # Essential YJIT metrics
│   └── activerecord.yml
├── exit-reports/            # Detailed exit reports
│   └── 20250115/
│       └── activerecord_yjit.txt
└── yjit_stats.html          # Stats dashboard
```

### Components

1. **`benchmark/collect_yjit_stats.rb`**: Minimal harness to collect stats inside Docker
2. **`lib/yjit_stats_processor.rb`**: Processes raw stats and calculates key metrics
3. **`lib/exit_report_formatter.rb`**: Generates human-readable exit reports
4. **`benchmark/ruby-bench.rb`**: Modified to collect stats when `--collect-stats` flag is used
5. **`bin/generate-stats-dashboard.rb`**: Creates HTML dashboard showing all stats

## Usage

### Running Benchmarks with Stats Collection

```bash
# Run specific benchmark with stats
./benchmark/ruby-bench.rb --collect-stats activerecord

# Run all benchmarks with stats
./benchmark/ruby-bench.rb --collect-stats

# Use the automated script with stats
./bin/ruby-kai1-with-stats.sh
```

### Generating Reports

```bash
# Generate stats dashboard
ruby bin/generate-stats-dashboard.rb

# Sync stats to git repository
bin/sync-results.rb all-stats
```

## Metrics Collected

### Essential Metrics (Stored in YAML)

- **ratio_in_yjit**: Percentage of instructions executed by YJIT (key metric)
- **avg_len_in_yjit**: Average instruction sequence length
- **inline_code_size**: Bytes of inlined machine code
- **outlined_code_size**: Bytes of outlined machine code
- **compiled_iseq_count**: Number of compiled methods
- **compiled_block_count**: Number of compiled blocks
- **invalidation_count**: Times compiled code was invalidated
- **invalidation_ratio**: Percentage of blocks invalidated
- **compile_time_ms**: Time spent compiling
- **top_exit_reasons**: Top 5 reasons YJIT exited to interpreter

### Exit Report Details

Each benchmark gets a detailed text report showing:

```
YJIT Exit Report
==================================================
Benchmark: activerecord
Date: 20250115
Ruby: abc123def
==================================================

YJIT Performance Metrics:
----------------------------------------
ratio_in_yjit:                 99.5%
avg_len_in_yjit:               2502.4

Code Generation:
----------------------------------------
inline_code_size:              5.3 MB
outlined_code_size:            419 KB

Compilation Statistics:
----------------------------------------
compiled_iseq_count:           1234
compiled_block_count:          5678
invalidation_count:            123
invalidation_ratio:            2.2%

Exit Statistics:
----------------------------------------
Top Exit Reasons:
  send_missing_method:         234 (23.4%)
  leave_se_interrupt:          123 (12.3%)
  ...
```

## Data Volume Considerations

### Storage Impact

- **Without stats**: ~1.7 KB/day (620 KB/year)
- **With essential stats + exit reports**: ~310 KB/day (113 MB/year)
- **Savings vs full stats**: 69% reduction compared to storing all 249 fields

### Why This Approach?

1. **Essential metrics only**: Stores 45 fields instead of 249
2. **Exit reports as text**: Human-readable format, smaller than JSON
3. **Maintains git workflow**: Keeps rubybench-data manageable
4. **On-demand regeneration**: Can re-run benchmarks if full data needed

## Requirements

### Docker Images

The Docker images must have Ruby compiled with `--yjit-stats` flag. The standard `ghcr.io/ruby/ruby:master-*` images should include this.

### Verification

To verify stats are available in a Docker container:

```bash
docker exec <container> ruby -e "puts defined?(RubyVM::YJIT.runtime_stats)"
```

## Integration with Existing System

### Backward Compatibility

- Existing YAML files remain unchanged
- Stats are stored separately
- Dashboard continues to work without stats
- Can be disabled with no impact

### Incremental Rollout

1. Test with subset of benchmarks first
2. Monitor storage growth
3. Enable for all benchmarks if successful

## Troubleshooting

### Stats Not Collecting

If stats aren't being collected:

1. Check Docker image has stats-enabled Ruby
2. Verify `--collect-stats` flag is used
3. Check for errors in console output
4. Ensure benchmark runs successfully first

### Storage Concerns

Monitor repository size:

```bash
cd results
du -sh yjit-stats/
du -sh exit-reports/
```

If growth exceeds projections, consider:
- Reducing number of stored metrics
- Archiving old exit reports
- Keeping only last N days of detailed data

## Future Enhancements

Potential improvements:

1. **Timeline graphs**: Show ratio_in_yjit trends over time
2. **Regression detection**: Alert when ratio_in_yjit drops
3. **Comparison views**: Compare stats across Ruby versions
4. **API access**: JSON endpoints for programmatic access
5. **Compression**: gzip old exit reports to save space

## Technical Details

### Key Calculations

**ratio_in_yjit**:
```ruby
side_exits = sum of all exit_* counters
retired_in_yjit = exec_instruction - side_exits
total_insns = retired_in_yjit + vm_insns_count
ratio_in_yjit = 100.0 * retired_in_yjit / total_insns
```

**invalidation_ratio**:
```ruby
invalidation_ratio = 100.0 * invalidation_count / compiled_block_count
```

### Exit Categories

Exit reasons are grouped by prefix:
- `send_*`: Method call exits
- `leave_*`: Method return exits
- `getivar_*`: Instance variable get exits
- `setivar_*`: Instance variable set exits
- `oaref_*`: Optimized array reference exits

## Contact

For questions or issues with YJIT stats collection, please open an issue in the rubybench repository.