
import std;
import xlsx;

fn void? write_xlsx(File file)
{
    XlsxWriter writer = xlsx::init_writer(&file)!;
    writer.write_string(1, 1, "Header", style: { .header = true })!;
    writer.write_double(1, 2, 13.21, style: { .header = true })!;
    writer.write_double(1, 3, xlsx::excel_days_from_date(2025, 1, 1), number_format: DATE, style: { .header = true })!;

    writer.write_string(2, 1, "Normal")!;
    writer.write_double(2, 2, 3.14)!;
    writer.write_double(2, 3, xlsx::excel_days_from_date(2025, 2, 28), number_format: DATE)!;
    writer.finalize_writer()!;
}

fn void main()
{
    File file = file::open("example.xlsx", "wb")!!;
    defer file.close()!!;

    write_xlsx(file)!!;
}
