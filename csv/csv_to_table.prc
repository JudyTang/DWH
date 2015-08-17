create or replace procedure csv_to_table(s in CLOB)
 as language java
    name 'CSVProcesser.processCSV(java.sql.Clob)';
/
