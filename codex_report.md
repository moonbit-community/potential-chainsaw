# Dependency check failed

Repository: potential-chainsaw

Command run:

```bash
moon check
```

Initial error:

```text
Error: Failed to calculate build plan

Caused by:
    0: Failed to solve package relationship
    1: Import tonyfettes/encoding@0.3.1 exists in global environment,
               but its containing module is not imported by peter-jerry-ye/io@0.3.2, thus cannot be imported by its package 'http'
```

Attempted fix:

```bash
moon add peter-jerry-ye/io
```

This updated `peter-jerry-ye/io` from `0.3.2` to `0.3.4`.

Error after update:

```text
Error: Failed to calculate build plan

Caused by:
    0: Failed to solve package relationship
    1: Import tonyfettes/encoding@0.3.7 exists in global environment,
               but its containing module is not imported by peter-jerry-ye/io@0.3.4, thus cannot be imported by its package 'http'
```

Conclusion:

`peter-jerry-ye/io` package `http` imports `tonyfettes/encoding`, but the module dependency is not declared by `peter-jerry-ye/io`. This prevents the current repository from calculating a build plan before source checks can run.
