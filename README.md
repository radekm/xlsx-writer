A C3 library for writing XLSX files in a streaming fashion.

Features of this library are:
- Constant memory usage that doesn't depend on the resulting XLSX file size.
- Support for cells with strings, numbers and dates.
- Support for header style and normal style.

## Usage

- Copy the directory `xlsx.c3l` to your project.
- When compiling your project
  - use `--lib xlsx` option
  - and if needed also use `--libdir path-to-xlsx-lib` where `path-to-xlsx-lib`
    is the path to a directory where `xlsx.c3l` was copied.
- Now you can import `xlsx` module in your project and use its functions.

## Contributions

We accept:

- ✅ Bug reports for the following platforms:
  - macOS on arm64
  - Windows 11 on x64
  - Linux on x64

We don't accept:

- ❌ Pull requests
- ❌ Feature requests
