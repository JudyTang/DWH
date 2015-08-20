CREATE OR REPLACE PACKAGE pkg_lw_presentationmeta_load IS

  PROCEDURE start_loading(p_file       IN VARCHAR2,
                          p_charset_id IN NUMBER,
                          p_fph_id_out OUT NUMBER);

END pkg_lw_presentationmeta_load;
/
