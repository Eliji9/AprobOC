"! <p class="shorttext synchronized">Aprob. automática OC: error controlado</p>
"! Error de una OC concreta (sin regla, conversión de moneda, etc.).
"! El motor lo captura por OC para que una OC con error no detenga la corrida.
CLASS zcx_mm_po_aut_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_text  TYPE string OPTIONAL
                previous TYPE REF TO cx_root OPTIONAL.

    METHODS get_text REDEFINITION.

  PRIVATE SECTION.
    DATA mv_text TYPE string.

ENDCLASS.



CLASS zcx_mm_po_aut_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    mv_text = iv_text.
  ENDMETHOD.


  METHOD get_text.
    result = COND #( WHEN mv_text IS NOT INITIAL THEN mv_text
                     WHEN previous IS BOUND      THEN previous->get_text( )
                     ELSE super->get_text( ) ).
  ENDMETHOD.

ENDCLASS.
