-- Create table
create global temporary table CSV_TO_TABLE_TMP
(
  LINE_NUMBER   NUMBER(38) not null,
  COLUMN_NUMBER NUMBER(38) not null,
  CELL_VALUE    VARCHAR2(1000)
)
on commit delete rows;