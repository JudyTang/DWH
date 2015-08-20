CREATE OR REPLACE PACKAGE pkg_lw_reportmeta_load IS

  -- Author  : U0143986
  -- Created : 7/24/2015 2:09:10 PM
  -- Purpose : 

  PROCEDURE start_loading(p_file       IN VARCHAR2,
                          p_charset_id IN NUMBER,
                          p_fph_id_out OUT NUMBER);

END pkg_lw_reportmeta_load;
/
