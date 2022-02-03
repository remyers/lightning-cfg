# Tips

To compare log files you can cut out date/time and detailed information:

```bash
    cut -d ' ' -f 3-5 -s eclair.log  > eclair-trimmed.log
```
