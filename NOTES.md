# Unused fill `gray125`

Fill `gray125` in `styles.xml` with index 1 is not used.
But our solid fill `FF93DCFA` for header cells doesn't work
when it has index 1. Following works:

```xml
<fills count="2">
    <fill>
        <patternFill patternType="none"/>
    </fill>
    <fill>
        <patternFill patternType="gray125"/>
    </fill>
    <fill>
        <patternFill patternType="solid">
            <fgColor rgb="FF93DCFA"/>
        </patternFill>
    </fill>
</fills>
```

# Non-existent date

Unfortunately Excel thinks that year 1900 is a leap year
and date 1900-02-29 exists. In reality it's not the case
but function `excel_days_from_date` must work with it.
