module xlsx;

import std;
import libc;

faultdef INVALID_XML_CHARACTER;

fn void? xml10_write_text(OutStream out, String s)
{
    foreach (Char32 c : s)
    {
        bool allowed = false;
        allowed = allowed || c == 0x09 || c == 0x0A || c == 0x0D;
        allowed = allowed || c >= 0x0020 && c <= 0xD7FF;
        allowed = allowed || c >= 0xE000 && c <= 0xFFFD;
        allowed = allowed || c >= 0x10000 && c <= 0x10FFFF;

        if (!allowed) return INVALID_XML_CHARACTER?;

        // Only `<` and `&` must be escaped in text.
        switch (c)
        {
            case '<':
                out.write("&lt;")!;
            case '&':
                out.write("&amp;")!;
            default:
                char[4] bytes;
                usz size = conv::char32_to_utf8(c, &bytes)!;
                out.write(bytes[:size])!;
        }
    }
}

fn void test_xml10_write_text() @test
{
    @pool()
    {
        DString s = dstring::temp();
        xml10_write_text(&s, "x < y && z")!!;
        assert("x &lt; y &amp;&amp; z" == s.str_view());

        s = dstring::temp();
        fault excuse = @catch(xml10_write_text(&s, "invalid character \x05 rest won't be visible"));
        assert("invalid character " == s.str_view());
        assert(INVALID_XML_CHARACTER == excuse);
    };
}

const uint INITIAL_CRC32 = 0xFFFFFFFF;

fn uint crc32_update(uint crc32, char byte)
{
    uint crc = crc32 ^ byte;
    for (int i = 0; i < 8; i++)
    {
        uint mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
    return crc;
}

fn uint crc32_finalize(uint crc32)
{
    return ~crc32;
}

fn uint crc32(String s)
{
    uint crc = INITIAL_CRC32;

    foreach (char byte : s)
    {
        crc = crc32_update(crc, byte);
    }
    return crc32_finalize(crc);
}

fn void test_crc32() @test
{
    assert(0xCBF43926 == crc32("123456789"));
    assert(0x0614A5CB == crc32("Hello world from CRC32!"));
}

macro void? write_le_ushort(stream, ushort s)
{
    stream.write_byte((char)s)!;
    stream.write_byte((char)(s >> 8))!;
}

macro void? write_le_uint(stream, uint s)
{
    stream.write_byte((char)s)!;
    stream.write_byte((char)(s >> 8))!;
    stream.write_byte((char)(s >> 16))!;
    stream.write_byte((char)(s >> 24))!;
}

// `file_name` is for a file name with a relative path.
// All slashes in `file_name` should be forward slashes `/`.
fn void? zip_write_local_file_header(OutStream out, String file_name)
{
    // Signature.
    out.write("PK\x03\x04")!;
    // Version: 2.0.
    write_le_ushort(out, 20)!;
    // Flags: 4th bit means that data descriptor is present.
    write_le_ushort(out, 1 << 3)!;
    // Compression method: no compression.
    write_le_ushort(out, 0)!;
    // Modification time.
    write_le_ushort(out, 0)!;
    // Modification date.
    write_le_ushort(out, 0)!;
    // CRC-32 - will be in data descriptor.
    write_le_uint(out, 0)!;
    // Compressed size - will be in data descriptor.
    write_le_uint(out, 0)!;
    // Uncompressed size - will be in data descriptor.
    write_le_uint(out, 0)!;
    // File name len.
    write_le_ushort(out, (ushort)file_name.len)!;
    // Extra field len.
    write_le_ushort(out, 0)!;
    // File name.
    out.write(file_name)!;
}

fn void? zip_write_data_descriptor(OutStream out, uint crc32, uint uncompressed_size)
{
    // CRC-32.
    write_le_uint(out, crc32)!;
    // Compressed size.
    write_le_uint(out, uncompressed_size)!;
    // Uncompressed size.
    write_le_uint(out, uncompressed_size)!;
}

// `file_name` is for a file name with a relative path.
// All slashes in `file_name` should be forward slashes `/`.
fn void? zip_write_central_directory_file_header(OutStream out, uint crc32, uint uncompressed_size, String file_name, uint local_file_header_offset)
{
    // Signature.
    out.write("PK\x01\x02")!;
    // Version made by: MS-DOS.
    write_le_ushort(out, 0)!;
    // PKZip version needed for extraction: 2.0.
    write_le_ushort(out, 20)!;
    // Flags: 4th bit means that data descriptor is present.
    write_le_ushort(out, 1 << 3)!;
    // Compression method: no compression.
    write_le_ushort(out, 0)!;
    // Modification time.
    write_le_ushort(out, 0)!;
    // Modification date.
    write_le_ushort(out, 0)!;
    // CRC-32.
    write_le_uint(out, crc32)!;
    // Compressed size.
    write_le_uint(out, uncompressed_size)!;
    // Uncompressed size.
    write_le_uint(out, uncompressed_size)!;
    // File name len.
    write_le_ushort(out, (ushort)file_name.len)!;
    // Extra field len.
    write_le_ushort(out, 0)!;
    // File comment len.
    write_le_ushort(out, 0)!;
    // Disk number where the file starts.
    write_le_ushort(out, 0)!;
    // Internal attributes.
    write_le_ushort(out, 0)!;
    // External attributes.
    write_le_uint(out, 0)!;
    // Offset of local file header.
    write_le_uint(out, local_file_header_offset)!;
    // File name.
    out.write(file_name)!;
}

fn void? zip_write_end_of_central_directory_record(OutStream out, ushort central_directory_entries, uint central_directory_size, uint central_directory_offset)
{
    // Signature.
    out.write("PK\x05\x06")!;
    // Number of this disk which contains the end of central directory record.
    write_le_ushort(out, 0)!;
    // Number of disk where central directory record starts.
    write_le_ushort(out, 0)!;
    // Disk entries - number of central directory entries on this disk.
    write_le_ushort(out, central_directory_entries)!;
    // Total entries - total number of central directory entries.
    write_le_ushort(out, central_directory_entries)!;
    // Central directory size.
    write_le_uint(out, central_directory_size)!;
    // Central directory offset on the disk on which central directory record starts.
    write_le_uint(out, central_directory_offset)!;
    // Comment length.
    write_le_ushort(out, 0)!;
}

fn void test_zip() @test
{
    @pool()
    {
        DString s = dstring::temp();

        String file_name = "greet.txt";
        String file_data = "Hello World!";

        zip_write_local_file_header(&s, file_name)!!;
        s.append_chars(file_data);
        zip_write_data_descriptor(&s, crc32(file_data), file_data.len)!!;
        uint central_directory_record_offset = (uint)s.len();
        zip_write_central_directory_file_header(&s, crc32(file_data), file_data.len, file_name, 0)!!;
        uint central_directory_record_size = (uint)s.len() - central_directory_record_offset;
        zip_write_end_of_central_directory_record(&s, 1, central_directory_record_size, central_directory_record_offset)!!;
    };
}

// For date `y-m-d` returns number of days after `1970-01-01`.
// Uses proleptic Gregorian calendar.
fn long days_from_civil(int y, char m, char d)
{
    // Implementation is taken from the article chrono-Compatible Low-Level Date Algorithms
    // by Howard Hinnant.

    // In our algorithm each year starts with March 1 and ends with February 28 or 29.
    // So if the month is 1 or 2 then it's actually previous year.
    y -= (int)(m <= 2);

    // Proleptic Gregorian calendar repeats after 400 years.
    // `era` specifies which 400 years we mean.
    // `era == -1` is for -0400-03-01 .. 0000-02-29.
    // `era == 0`  is for  0000-03-01 .. 0400-02-29.
    // `era == 1`  is for  0400-03-01 .. 0800-02-29.
    // `era == 5`  is for  2000-03-01 .. 2400-02-29.
    long era = (y >= 0 ? (long)y : (long)y-399) / 400;

    // Year of era.
    long yoe = y - era * 400;  // [0, 399]
    // Day of year.
    // `m > 2 ? m-3 : m+9` is month index where March has 0, April has 1, .., February has 11.
    // `d-1` is day of current month.
    // `(153 * month_index + 2) / 5` is one of several linear polynomials which
    // returns total number of days in months before month with given index.
    long doy = (153*(m > 2 ? (long)m-3 : (long)m+9) + 2)/5 + (long)d-1;  // [0, 365]
    // Day of era.
    long doe = yoe * 365 + yoe/4 - yoe/100 + doy;  // [0, 146096]
    // Each era has 146097 days.
    // `era * 146097 + doe` returns number of days after `0000-03-01`.
    // We subtract `719468` to get number of days after `1970-01-01`.
    return era * 146097 + doe - 719468;
}

// Excel counts days since 1899-12-31.
// First valid Excel date is 1900-01-01 and for it Excel returns 1.
// Unfortunately Excel thinks that 1900-02-29 exists but that is not the case.
fn long excel_days_from_date(int y, char m, char d)
{
    return days_from_civil(y, m, d) - days_from_civil(1899, 12, 31) + (long)!(y == 1900 && m <= 2);
}

fn void test_excel_days_from_date() @test
{
    assert(1 == excel_days_from_date(1900, 1, 1));
    assert(2 == excel_days_from_date(1900, 1, 2));
    assert(31 == excel_days_from_date(1900, 1, 31));
    assert(32 == excel_days_from_date(1900, 2, 1));
    assert(59 == excel_days_from_date(1900, 2, 28));
    assert(60 == excel_days_from_date(1900, 2, 29));  // This date doesn't exist but Excel thinks it does.
    assert(61 == excel_days_from_date(1900, 3, 1));
    assert(36_372 == excel_days_from_date(1999, 7, 31));
    assert(36_586 == excel_days_from_date(2000, 3, 1));
    assert(38_047 == excel_days_from_date(2004, 3, 1));
    assert(2_958_465 == excel_days_from_date(9999, 12, 31));
}

// Returns array terminated by zero.
// `column` has range 1 .. 16384.
fn char[4] excel_column_name_from_number(int column)
{
    char[4] name;
    // 3 letters.
    if (column > 702)
    {
        column -= 703;
        name[2] = 'A' + (char)(column % 26);
        column /= 26;
        name[1] = 'A' + (char)(column % 26);
        column /= 26;
        name[0] = 'A' + (char)column;
    }
    // 2 letters.
    else if (column > 26)
    {
        column -= 27;
        name[1] = 'A' + (char)(column % 26);
        column /= 26;
        name[0] = 'A' + (char)column;
    }
    // 1 letter.
    else
    {
        column -= 1;
        name[0] = 'A' + (char)column;
    }
    return name;
}

fn void test_excel_column_name_from_number() @test
{
    assert(libc::strcmp("A", (ZString)&&excel_column_name_from_number(1)) == 0);
    assert(libc::strcmp("Z", (ZString)&&excel_column_name_from_number(26)) == 0);
    assert(libc::strcmp("AA", (ZString)&&excel_column_name_from_number(27)) == 0);
    assert(libc::strcmp("AZ", (ZString)&&excel_column_name_from_number(52)) == 0);
    assert(libc::strcmp("TI", (ZString)&&excel_column_name_from_number(529)) == 0);
    assert(libc::strcmp("ZZ", (ZString)&&excel_column_name_from_number(702)) == 0);
    assert(libc::strcmp("AAA", (ZString)&&excel_column_name_from_number(703)) == 0);
    assert(libc::strcmp("XFD", (ZString)&&excel_column_name_from_number(16_384)) == 0);
}

struct OutStreamWithCrc (OutStream)
{
    OutStream inner;
    uint crc32;
    usz written;
}

fn usz? OutStreamWithCrc.write(&self, char[] bytes) @dynamic
{
    usz written = self.inner.write(bytes)!;
    uint crc32 = self.crc32;
    foreach (char c : bytes[:written])
    {
        crc32 = crc32_update(crc32, c);
    }
    self.crc32 = crc32;
    self.written += written;
	return written;
}

fn void? OutStreamWithCrc.write_byte(&self, char c) @dynamic
{
    self.inner.write_byte(c)!;
    self.crc32 = crc32_update(self.crc32, c);
    self.written++;
}

struct XlsxWriter
{
    OutStreamWithCrc out;
    uint sheet_data_offset;
    int last_row;
    int last_column;
}

struct XlsxStyle
{
    bool header;
}

enum XlsxNumberFormat
{
    DEFAULT,
    DATE,
}

fn XlsxWriter? init_writer(OutStream out)
{
    XlsxWriter writer;
    writer.out.inner = out;

    zip_write_local_file_header(&writer.out, "xl/worksheets/sheet1.xml")!;

    writer.out.crc32 = INITIAL_CRC32;
    writer.sheet_data_offset = (uint)writer.out.written;
    writer.out.write(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`)!;
    writer.out.write("\n")!;
    writer.out.write(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">`)!;
    writer.out.write(`<sheetData>`)!;

    return writer;
}

fn void? XlsxWriter.finalize_writer(XlsxWriter* self)
{
    // Close last row.
    if (self.last_row != 0)
    {
        self.out.write("</row>")!;
    }

    self.out.write(`</sheetData>`)!;
    self.out.write(`</worksheet>`)!;

    uint sheet_crc32 = crc32_finalize(self.out.crc32);
    uint sheet_size = (uint)self.out.written - (uint)self.sheet_data_offset;

    zip_write_data_descriptor(&self.out, sheet_crc32, sheet_size)!;

    // Store remaining files.
    const int N = 6;
    String[N] data = {
        CONTENT_TYPES_XML,
        DOT_RELS,
        CORE_XML,
        STYLES_XML,
        WORKBOOK_XML,
        WORKBOOK_XML_RELS,
    };
    String[N] file_names = {
        "[Content_Types].xml",
        "_rels/.rels",
        "docProps/core.xml",
        "xl/styles.xml",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
    };
    uint[N] offsets;
    uint[N] crcs32;
    for (int i = 0; i < N; i++)
    {
        offsets[i] = (uint)self.out.written;
        zip_write_local_file_header(&self.out, file_names[i])!;
        self.out.crc32 = INITIAL_CRC32;
        self.out.write(data[i])!;
        crcs32[i] = crc32_finalize(self.out.crc32);
        zip_write_data_descriptor(&self.out, crcs32[i], data[i].len)!;
    }

    // Central directory record.
    uint central_directory_offset = (uint)self.out.written;
    zip_write_central_directory_file_header(&self.out, sheet_crc32, sheet_size, "xl/worksheets/sheet1.xml", 0)!;
    for (int i = 0; i < N; i++)
    {
        zip_write_central_directory_file_header(&self.out, crcs32[i], data[i].len, file_names[i], offsets[i])!;
    }
    uint central_directory_size = (uint)self.out.written - central_directory_offset;

    zip_write_end_of_central_directory_record(&self.out, N + 1, central_directory_size, central_directory_offset)!;
}

// `style_index` refers to `<xf>` in `<cellXfs>`.
fn void? prepare_for_writing_cell(XlsxWriter* writer, int row, int column, String cell_type, int style_index)
{
    assert(writer.last_row <= row);
    assert(writer.last_row != row || writer.last_column < column);
    if (writer.last_row != row)
    {
        // Close current row.
        if (writer.last_row != 0)
        {
            writer.out.write("</row>")!;
        }
        // Open new row.
        io::fprintf(&writer.out, "<row r=\"%d\">", row)!;
    }

    // Open cell.
    io::fprintf(&writer.out, "<c r=\"%s%d\"", (ZString)&&excel_column_name_from_number(column), row)!;
    if (cell_type != "") io::fprintf(&writer.out, " t=\"%s\"", cell_type)!;
    if (style_index != 0) io::fprintf(&writer.out, " s=\"%d\"", style_index)!;
    writer.out.write(">")!;

    writer.last_row = row;
    writer.last_column = column;
}

fn void? XlsxWriter.write_string(XlsxWriter* self, int row, int column, String s, XlsxStyle style = {})
{
    int style_index = style.header ? 2 : 0;
    prepare_for_writing_cell(self, row, column, "inlineStr", style_index)!;
    io::fprintf(&self.out, "<is><t>")!;  // Inline string / text.
    xml10_write_text(&self.out, s)!;
    io::fprintf(&self.out, "</t></is>")!;
    io::fprintf(&self.out, "</c>")!;
}

fn void? XlsxWriter.write_double(XlsxWriter* self, int row, int column, double x, XlsxNumberFormat number_format = {}, XlsxStyle style = {})
{
    int style_index = style.header ? (number_format == DATE ? 3 : 2) : (number_format == DATE ? 1 : 0);
    prepare_for_writing_cell(self, row, column, "", style_index)!;
    io::fprintf(&self.out, "<v>%.17g</v>", x)!;
    io::fprintf(&self.out, "</c>")!;
}

const String CONTENT_TYPES_XML = $embed("data/[Content_Types].xml");
const String DOT_RELS = $embed("data/_rels/.rels");
const String CORE_XML = $embed("data/docProps/core.xml");
const String STYLES_XML = $embed("data/xl/styles.xml");
const String WORKBOOK_XML = $embed("data/xl/workbook.xml");
const String WORKBOOK_XML_RELS = $embed("data/xl/_rels/workbook.xml.rels");
