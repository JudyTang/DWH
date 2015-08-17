create or replace function process_excel (s in varchar2)
      return varchar2
 as language java
    name 'ExcelProcesser.processExcel(java.lang.String) return java.lang.String';
/
