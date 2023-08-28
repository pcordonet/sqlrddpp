/* $CATEGORY$SQLRDD/Utils$FILES$sql.lib$
* SQLRDD Utilities
* Copyright (c) 2003 - Marcelo Lombardo  <lombardo@uol.com.br>
* All Rights Reserved
*/

/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA (or visit the web site http://www.gnu.org/).
 *
 * As a special exception, the xHarbour Project gives permission for
 * additional uses of the text contained in its release of xHarbour.
 *
 * The exception is that, if you link the xHarbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the xHarbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the xHarbour
 * Project under the name xHarbour.  If you copy code from other
 * xHarbour Project or Free Software Foundation releases into a copy of
 * xHarbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for xHarbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

#include "hbclass.ch"
#include "common.ch"
// #include "compat.ch"
#include "sqlodbc.ch"
#include "sqlrdd.ch"
#include "fileio.ch"
#include "msg.ch"
#include "error.ch"
#include "sqlrddsetup.ch"

#define SR_CRLF   (chr(13) + chr(10))

REQUEST HB_Deserialize
REQUEST HB_DeserialNext
#define FH_ALLOC_BLOCK     32

Static DtAtiv, lHistorico
Static _nCnt := 1
Static lCreateAsHistoric := .F.

#ifdef HB_C52_UNDOC
STATIC s_lNoAlert
#endif

/*------------------------------------------------------------------------*/

FUNCTION SR_GoPhantom()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):sqlGoPhantom()
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_WorkareaFileName()

   if empty(alias())
      RETURN ""
   endif

   if !IS_SQLRDD
      RETURN ""
   endif

RETURN dbInfo(DBI_INTERNAL_OBJECT):cFileName

/*------------------------------------------------------------------------*/

FUNCTION SR_dbStruct()

   if empty(alias())
      RETURN {}
   endif

   if !IS_SQLRDD
      RETURN {}
   endif

RETURN aclone(dbInfo(DBI_INTERNAL_OBJECT):aFields)

/*------------------------------------------------------------------------*/

FUNCTION SR_MsgLogFile(uMsg, p1, p2, p3, p4, p5, p6, p7, p8)
   SR_LogFile("sqlerror.log", {uMsg, p1, p2, p3, p4, p5, p6, p7, p8})
RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_Val2Char(a, n1, n2)
   Do Case
   Case HB_ISSTRING(a) 
      RETURN a
   Case HB_ISNUMERIC(a) .AND. n1 != NIL .AND. n2 != NIL
      RETURN Str(a, n1, n2)
   Case HB_ISNUMERIC(a)
      RETURN Str(a)
   Case HB_ISDATE(a)
      RETURN dtoc(a)
   Case HB_ISLOGICAL(a) 
      RETURN iif(a, ".T.", ".F.")
   EndCase
RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION SR_LogFile(cFileName, aInfo, lAddDateTime)

   LOCAL hFile
   LOCAL cLine
   LOCAL n

   Default lAddDatetime TO .T.

   If lAddDateTime

      cLine := DToC(Date()) + " " + Time() + ": "

   Else

      cLine := ""

   Endif

   FOR n := 1 TO Len(aInfo)
      If aInfo[n] == NIL
         Exit
      EndIf
      cLine += SR_Val2CharQ(aInfo[n]) + Chr(9)
   NEXT n

   cLine += SR_CRLF

   IF sr_phFile(cFileName)
      hFile := FOpen(cFileName, 1)
   ELSE
      hFile := FCreate(cFileName)
   ENDIF

   FSeek(hFile, 0, 2)
   FWrite(hFile, alltrim(cLine))
   FClose(hFile)

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_FilterStatus(lEnable)

   If IS_SQLRDD
      If HB_ISLOGICAL(lEnable) 
         RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):lDisableFlts := !lEnable
      Else
         RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):lDisableFlts
      EndIf
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_CreateConstraint(aSourceColumns, cTargetTable, aTargetColumns, cConstraintName)

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):CreateConstraint(dbInfo(DBI_INTERNAL_OBJECT):cFileName, aSourceColumns, cTargetTable, aTargetColumns, cConstraintName)
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_DropConstraint(cConstraintName, lFKs)

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):DropConstraint(dbInfo(DBI_INTERNAL_OBJECT):cFileName, cConstraintName, lFKs)
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_ChangeStruct(cTableName, aNewStruct)

   LOCAL oWA
   LOCAL lOk := .T.
   LOCAL aToDrop := {}
   LOCAL aToFix := {}
   LOCAL i
   LOCAL n
   LOCAL cAlias
   LOCAL nReg
   LOCAL cTblName
   LOCAL nAlias
   LOCAL nOrd
   LOCAL aDirect := {}

   If select() == 0
      SR_RuntimeErr(, "SR_ChengeStructure: Workarea not in use.")
   EndIf

   If len(aNewStruct) < 1 .OR. !HB_ISARRAY(aNewStruct) .OR. !HB_ISARRAY(aNewStruct[1])
      SR_RuntimeErr(, "SR_ChengeStructure: Invalid arguments [2].")
   EndIf

   If IS_SQLRDD

      oWA := dbInfo(DBI_INTERNAL_OBJECT)

      If (!Empty(cTableName)) .AND. oWA:cOriginalFN != upper(alltrim(cTableName))
         SR_RuntimeErr(, "SR_ChengeStructure: Invalid arguments [1]: " + cTableName)
      EndIf

      cAlias   := alias()
      nAlias   := select()
      cTblName := oWA:cFileName
      nOrd     := IndexOrd()
      nReg     := recno()

      dbSetOrder(0)

      SR_LogFile("changestruct.log", { oWA:cFileName, "Original Structure:", e"\r\n" + sr_showVector(oWA:aFields)  })
      SR_LogFile("changestruct.log", { oWA:cFileName, "New Structure:", e"\r\n" + sr_showVector(aNewStruct)  })

      FOR i := 1 TO len(aNewStruct)
         aNewStruct[i, 1] := Upper(alltrim(aNewStruct[i, 1]))
         If (n := aScan(oWA:aFields, {|x| x[1] == aNewStruct[i, 1] }) ) > 0

            aSize(aNewStruct[i], max(len(aNewStruct[i] ), 5))

            If aNewStruct[i, 2] == oWA:aFields[n, 2] .AND. aNewStruct[i, 3] == oWA:aFields[n, 3] .AND. aNewStruct[i, 4] == oWA:aFields[n, 4]
               // Structure is identical. Only need to check for NOT NULL flag.
               If aNewStruct[i, FIELD_NULLABLE] != NIL .AND. aNewStruct[i, FIELD_NULLABLE] !=  oWA:aFields[n, FIELD_NULLABLE]
                  If aNewStruct[i, FIELD_NULLABLE]
                     SR_LogFile("changestruct.log", { oWA:cFileName, "Changing to nullable:", aNewStruct[i, 1]})
                     oWA:DropRuleNotNull(aNewStruct[i, 1])
                  Else
                     SR_LogFile("changestruct.log", { oWA:cFileName, "Changing to not null:", aNewStruct[i, 1]})
                     oWA:AddRuleNotNull(aNewStruct[i, 1])
                  EndIf
               EndIf
            ElseIf oWA:oSql:nSystemID == SYSTEMID_IBMDB2
               SR_LogFile("changestruct.log", { oWA:cFileName, "Column cannot be changed:", aNewStruct[i, 1], " - Operation not supported by back end database" })
            ElseIf aNewStruct[i, 2] == "M" .AND. oWA:aFields[n, 2] == "C"
               aadd(aToFix, aClone(aNewStruct[i]))
               SR_LogFile("changestruct.log", { oWA:cFileName, "Will Change data type of field:", aNewStruct[i, 1], "from", oWA:aFields[n, 2], "to", aNewStruct[i, 2]})
            ElseIf aNewStruct[i, 2] == "C" .AND. oWA:aFields[n, 2] == "M"
               aadd(aToFix, aClone(aNewStruct[i]))
               SR_LogFile("changestruct.log", { oWA:cFileName, "Warning: Possible data loss changing data type:", aNewStruct[i, 1], "from", oWA:aFields[n, 2], "to", aNewStruct[i, 2]})
            ElseIf aNewStruct[i, 2] != oWA:aFields[n, 2]
               IF aNewStruct[i, 2] $"CN" .AND. oWA:aFields[n, 2] $"CN" .AND. oWA:oSql:nSystemID == SYSTEMID_POSTGR

*                   IF "8.4" $ oWA:oSql:cSystemVers .OR. "9.0" $ oWA:oSql:cSystemVers
                  IF oWA:oSql:lPostgresql8 .AND. !oWA:oSql:lPostgresql83
                     aadd(aDirect, aClone(aNewStruct[i]))
                  else
                     aadd(aToFix, aClone(aNewStruct[i]))
                  ENDIF
                  SR_LogFile("changestruct.log", { oWA:cFileName, "Warning: Possible data loss changing field types:", aNewStruct[i, 1], "from", oWA:aFields[n, 2], "to", aNewStruct[i, 2]})
               ELSE
                  SR_LogFile("changestruct.log", { oWA:cFileName, "ERROR: Cannot convert data type of field:", aNewStruct[i, 1], " from", oWA:aFields[n, 2], "to", aNewStruct[i, 2] })
               ENDIF
            ElseIf aNewStruct[i, 3] >= oWA:aFields[n, 3] .AND. oWA:aFields[n, 2] $ "CN"

               aadd(aDirect, aClone(aNewStruct[i]))
               SR_LogFile("changestruct.log", { oWA:cFileName, "Will Change field size:", aNewStruct[i, 1], "from", oWA:aFields[n, 3], "to", aNewStruct[i, 3] })
            ElseIf aNewStruct[i, 3] < oWA:aFields[n, 3] .AND. oWA:aFields[n, 2] $ "CN"
               aadd(aToFix, aClone(aNewStruct[i]))
               SR_LogFile("changestruct.log", { oWA:cFileName, "Warning: Possible data loss changing field size:", aNewStruct[i, 1], "from", oWA:aFields[n, 3], "to", aNewStruct[i, 3]})
            Else
               SR_LogFile("changestruct.log", { oWA:cFileName, "Column cannot be changed:", aNewStruct[i, 1] })
            EndIf
         Else
            aadd(aToFix, aClone(aNewStruct[i]))
            SR_LogFile("changestruct.log", { oWA:cFileName, "Will add column:", aNewStruct[i, 1] })
         EndIf
      NEXT i

      FOR i := 1 TO len(oWA:aFields)
         If (n := aScan(aNewStruct, {|x| x[1] == oWA:aFields[i, 1] }) ) == 0
            If (!oWA:aFields[i, 1] == oWA:cRecnoName) .AND. (!oWA:aFields[i, 1] == oWA:cDeletedName ) .AND. oWA:oSql:nSystemID != SYSTEMID_IBMDB2
               aadd(aToDrop, aClone(oWA:aFields[i]))
               SR_LogFile("changestruct.log", { oWA:cFileName, "Will drop:", oWA:aFields[i, 1] })
            EndIf
         EndIf
      NEXT i
      IF Len(aDirect) > 0 .AND.;
       ( oWA:oSql:nSystemID == SYSTEMID_FIREBR .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_FIREBR3 .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_MYSQL  .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_MARIADB  .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_ORACLE .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_MSSQL6 .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_MSSQL7 .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_CACHE  .OR. ;
         oWA:oSql:nSystemID == SYSTEMID_POSTGR )

         oWA:AlterColumnsDirect(aDirect, .T., .F., @aTofix)
      ENDIF

      If len(aToFix) > 0
         oWA:AlterColumns(aToFix, .T.)
      EndIf

      FOR i := 1 TO len(aToDrop)
         If aToDrop[i, 1] == "BACKUP_"
            oWA:DropColumn(aToDrop[i, 1], .F.)
         Else
            oWA:DropColumn(aToDrop[i, 1], .T.)
         EndIf
      NEXT i

      SELECT (nALias)
      dbCloseArea()

      SR_CleanTabInfoCache()

      // recover table status

      SELECT (nAlias)
      dbUseArea(.F., "SQLRDD", cTblName, cAlias)
      If OrdCount() >= nOrd
         dbSetOrder(nOrd)
      EndIf
      dbGoTo(nReg)

   Else
      SR_RuntimeErr(, "SR_ChengeStructure: Not a SQLRDD workarea.")
   EndIf

RETURN lOk

/*------------------------------------------------------------------------*/

FUNCTION SR_SetCurrDate(d)

   If IS_SQLRDD
      d := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):SetCurrDate(d)
      If d == NIL
         d := SR_GetActiveDt()
      EndIf
   EndIf

RETURN d

/*------------------------------------------------------------------------*/

FUNCTION SR_QuickAppend(l)

   If IS_SQLRDD
      l := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):SetQuickAppend(l)
   EndIf

RETURN l

/*------------------------------------------------------------------------*/

FUNCTION SR_SetColPK(cColName)

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):SetColPK(cColName)
      If cColName == NIL
         cColName := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):cColPK
      EndIf
   EndIf

RETURN cColName

/*------------------------------------------------------------------------*/

FUNCTION SR_IsWAHist()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):lHistoric
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_SetReverseIndex(nIndex, lSet)

   LOCAL lOldSet

   If IS_SQLRDD .AND. nIndex > 0 .AND. nIndex <= len((Select())->(dbInfo(DBI_INTERNAL_OBJECT)):aIndex)
      lOldSet := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):aIndex[nIndex, DESCEND_INDEX_ORDER]
      If HB_ISLOGICAL(lSet)
         (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):aIndex[nIndex, DESCEND_INDEX_ORDER] := lSet
      EndIf
   EndIf

RETURN lOldSet

/*------------------------------------------------------------------------*/

FUNCTION SR_SetNextDt(d)

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):SetNextDt(d)
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_DisableHistoric()

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):DisableHistoric()
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):Refresh()
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_EnableHistoric()

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):EnableHistoric()
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):Refresh()
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_GetActiveDt()

RETURN DtAtiv

/*------------------------------------------------------------------------*/

FUNCTION SR_SetActiveDt(d)

   DEFAULT d TO date()

RETURN DtAtiv := d

/*------------------------------------------------------------------------*/

FUNCTION SR_SetActiveDate(d)

   LOCAL dOld := DtAtiv

   If d != NIL
      DtAtiv := d
   EndIf

RETURN dOld

/*------------------------------------------------------------------------*/

Init Procedure SR_IniDtAtiv()

   DtAtiv := date()

Return

/*------------------------------------------------------------------------*/

FUNCTION SR_SetCreateAsHistoric(l)

   LOCAL lOld := lCreateAsHistoric

   If HB_ISLOGICAL(l) 
      lCreateAsHistoric := l
   EndIf

RETURN lCreateAsHistoric

/*------------------------------------------------------------------------*/

FUNCTION SR_HasHistoric()

RETURN (lHistorico := .T.)

/*------------------------------------------------------------------------*/

FUNCTION SR_cDBValue(uData, nSystemID)

   default nSystemID TO SR_GetConnection():nSystemID

RETURN SR_SubQuoted(valtype(uData), uData, nSystemID)

/*------------------------------------------------------------------------*/

STATIC FUNCTION SR_SubQuoted(cType, uData, nSystemID)

   LOCAL cRet
   LOCAL cOldSet := SET(_SET_DATEFORMAT)

   Do Case // TODO: switch ?
   Case cType $ "CM" .AND. nSystemID == SYSTEMID_ORACLE
      RETURN "'" + rtrim(strtran(uData, "'", "'||" + "CHR(39)" + "||'")) + "'"
   Case cType $ "CM" .AND. nSystemID == SYSTEMID_MSSQL7
      RETURN "'" + rtrim(strtran(uData, "'", "'" + "'")) + "'"
   Case cType $ "CM" .AND. nSystemID == SYSTEMID_POSTGR
      RETURN "E'" + strtran(rtrim(strtran(uData, "'", "'" + "'")), "\", "\\") + "'"
   Case cType $ "CM"
      RETURN "'" + rtrim(strtran(uData, "'", "")) + "'"
   Case cType == "D" .AND. nSystemID == SYSTEMID_ORACLE
      RETURN "TO_DATE('" + rtrim(DtoS(uData)) + "','YYYYMMDD')"
    Case cType == "D" .AND. (nSystemID == SYSTEMID_IBMDB2 .OR. nSystemID == SYSTEMID_ADABAS )
        RETURN "'"+transform(DtoS(uData) ,'@R 9999-99-99')+"'"
   Case cType == "D" .AND. nSystemID == SYSTEMID_SQLBAS
      RETURN "'" + SR_dtosDot(uData) + "'"
   Case cType == "D" .AND. nSystemID == SYSTEMID_INFORM
      RETURN "'" + SR_dtoUS(uData) + "'"
   Case cType == "D" .AND. nSystemID == SYSTEMID_INGRES
      RETURN "'" + SR_dtoDot(uData) + "'"
   Case cType == "D" .AND. (nSystemID == SYSTEMID_FIREBR .OR. nSystemID == SYSTEMID_FIREBR3)
      RETURN "'"+transform(DtoS(uData) ,'@R 9999/99/99')+"'"

   Case cType == "D" .AND. nSystemID == SYSTEMID_CACHE
      RETURN "{d '" + transform(DtoS(iif(year(uData) < 1850, stod("18500101"), uData)), "@R 9999-99-99") + "'}"
   Case cType == "D"
      RETURN "'" + dtos(uData) + "'"
   Case cType == "N"
      RETURN ltrim(str(uData))
   Case cType == "L" .AND. (nSystemID == SYSTEMID_POSTGR .OR. nSystemID == SYSTEMID_FIREBR3 )
      RETURN iif(uData, "true", "false")
   Case cType == "L" .AND. nSystemID == SYSTEMID_INFORM
      RETURN iif(uData, "'t'", "'f'")
   Case cType == "L"
      RETURN iif(uData, "1", "0")
   case ctype == "T"  .AND. nSystemID == SYSTEMID_POSTGR
      IF Empty(uData)
         RETURN 'NULL'
      ENDIF

      RETURN "'" + transform(ttos(uData), '@R 9999-99-99 99:99:99') + "'"
   case ctype == "T" .AND. nSystemID == SYSTEMID_ORACLE
      IF Empty(uData)
         RETURN 'NULL'
      ENDIF
      RETURN [ TIMESTAMP '] + transform(ttos(uData), '@R 9999-99-99 99:99:99') + "'"
   Case cType == 'T'
      IF Empty(uData)
         RETURN 'NULL'
      ENDIF
      Set(_SET_DATEFORMAT, "yyyy-mm-dd")
      cRet := ttoc(uData)
      Set(_SET_DATEFORMAT, cOldSet)
      RETURN "'"+cRet+"'"
      
   OtherWise
      cRet := SR_STRTOHEX(HB_Serialize(uData))
      RETURN SR_SubQuoted("C", SQL_SERIALIZED_SIGNATURE + str(len(cRet), 10) + cRet, nSystemID)
   EndCase

RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION SR_WriteTimeLog(cComm, oCnn, nLimisencos)

   LOCAL nAlAtual := Select()
   LOCAL TRACE_STRUCT := { ;
                            { "USUARIO",    "C", 10, 0 },;
                            { "DATA",       "D", 08, 0 },;
                            { "HORA",       "C", 08, 0 },;
                            { "CONTADOR",   "C", 01, 0 },;
                            { "TRANSCOUNT", "N", 10, 0 },;
                            { "COMANDO",    "M", 10, 0 },;
                            { "CUSTO",      "N", 12, 0 } ;
                         }

   HB_SYMBOL_UNUSED(oCnn)

   BEGIN SEQUENCE

      If !sr_PhFile("long_qry.dbf")
         dbCreate("long_qry.dbf", TRACE_STRUCT, "DBFNTX")
      EndIf

      DO WHILE .T.
         dbUseArea(.T., "DBFNTX", "long_qry.dbf", "LONG_QRY", .T., .F.)
         If !NetErr()
            exit
         EndIf
         ThreadSleep(500)
      ENDDO

      LONG_QRY->(dbAppend())
      Replace LONG_QRY->DATA         with Date()
      Replace LONG_QRY->HORA         with Time()
      Replace LONG_QRY->COMANDO      with cComm
      Replace LONG_QRY->CUSTO        with nLimisencos
      LONG_QRY->(dbCloseArea())

   RECOVER

   END SEQUENCE

   dbSelectArea(nAlAtual)

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_uCharToVal(cVal, cType, nLen)

   SWITCH cType
   CASE "C"
      IF nLen == NIL
         RETURN cVal
      ELSE
         RETURN PadR(cVal, nLen)
      ENDIF
   CASE "M"
      RETURN cVal
   CASE "D"
      RETURN ctod(cVal)
   CASE "N"
      RETURN val(cVal)
   CASE "L"
      RETURN cVal $ "1.T.SYsy.t."
   ENDSWITCH

RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION SR_WriteDbLog(cComm, oCnn)

   LOCAL nAlAtual := Select()
   LOCAL TRACE_STRUCT := { ;
                            { "USUARIO",    "C", 10, 0 },;
                            { "DATA",       "D", 08, 0 },;
                            { "HORA",       "C", 08, 0 },;
                            { "CONTADOR",   "C", 01, 0 },;
                            { "TRANSCOUNT", "N", 10, 0 },;
                            { "COMANDO",    "M", 10, 0 } ;
                         }

   HB_SYMBOL_UNUSED(oCnn)

   DEFAULT cComm TO ""

   BEGIN SEQUENCE

      If !sr_phFile("sqllog.dbf")
         dbCreate("sqllog.dbf", TRACE_STRUCT, "DBFNTX")
      EndIf

      DO WHILE .T.
         dbUseArea(.T., "DBFNTX", "sqllog.dbf", "SQLLOG", .T., .F.)
         If !NetErr()
            EXIT
         EndIf
         ThreadSleep(500)
      ENDDO

      SQLLOG->(dbAppend())
      Replace SQLLOG->DATA         with Date()
      Replace SQLLOG->HORA         with Time()
      Replace SQLLOG->COMANDO      with cComm
      SQLLOG->(dbCloseArea())

   RECOVER

   END SEQUENCE

   dbSelectArea(nAlAtual)

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_ShowVector(a)

   LOCAL cRet := ""
   LOCAL i

   If HB_ISARRAY(a) 

      cRet := "{"

      FOR i := 1 TO len(a)

         If HB_ISARRAY(a[i])
            cRet += SR_showvector(a[i]) + iif(i == len(a), "", ",") + SR_CRLF
         Else
            cRet += SR_Val2CharQ(a[i]) + iif(i == len(a), "", ",")
         EndIf

      NEXT i

      cRet += "}"

   Else

      cRet += SR_Val2CharQ(a)

   EndIf

RETURN cRet

/*------------------------------------------------------------------------*/

FUNCTION SR_Val2CharQ(uData)

   LOCAL cType := valtype(uData)

   SWITCH cType
   CASE "C"
      //RETURN (["] + uData + ["])
      RETURN AllTrim(uData)
   CASE "N"
      RETURN alltrim(Str(uData))
   CASE "D"
      RETURN dtoc(uData)
   CASE "T"
      RETURN ttoc(uData)
   CASE "L"
      RETURN iif(uData, ".T.", ".F.")
   CASE "A"
      RETURN "{Array}"
   CASE "O"
      RETURN "{Object}"
   CASE "B"
      RETURN "{||Block}"
   OTHERWISE
      RETURN "NIL"
   ENDSWITCH

RETURN "NIL"

/*------------------------------------------------------------------------*/

FUNCTION SR_BlankVar(cType, nLen, nDec)

   LOCAL nVal

   HB_SYMBOL_UNUSED(nDec) // To remove warning

   SWITCH cType
   CASE "C"
   CASE "M"
      RETURN Space(nLen)
   CASE "L"
      RETURN .F.
   CASE "D"
      RETURN ctod("")
   CASE "N"
      IF nDec > 0
         SWITCH ndec
         CASE 1
            nVal := 0.0
            EXIT
         CASE 2
            nVal := 0.00
            EXIT
         CASE 3
            nVal := 0.000
            EXIT
         CASE 4
            nVal := 0.0000
            EXIT
         CASE 5
            nVal := 0.00000
            EXIT
         CASE 6
            nVal := 0.000000
            EXIT
         OTHERWISE
            nVal := 0.00
         ENDSWITCH
         RETURN nVal
      ENDIF
      RETURN 0
   CASE "T"
      RETURN datetime(0, 0, 0, 0, 0, 0, 0)
   ENDSWITCH

RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION SR_HistExpression(n, cTable, cPK, CurrDate, nSystem)

   LOCAL cRet
   LOCAL cAl1
   LOCAL cAl2
   LOCAL cAlias
   LOCAL oCnn

   oCnn := SR_GetConnection()

   cAlias := "W" + StrZero(++_nCnt, 3)
   cAl1   := "W" + StrZero(++_nCnt, 3)
   cAl2   := "W" + StrZero(++_nCnt, 3)

   If _nCnt >= 995
      _nCnt := 1
   EndIf

   DEFAULT CurrDate TO SR_GetActiveDt()
   DEFAULT n TO 0
   DEFAULT nSystem TO oCnn:nSystemID

   cRet := "SELECT " + cAlias + ".* FROM " + cTable + " " + cAlias + " WHERE " + SR_CRLF

   cRet += "(" + cAlias + ".DT__HIST = (SELECT" + iif(n = 3, " MIN(", " MAX(") + cAl1 + ".DT__HIST) FROM "
   cRet += cTable + " " + cAl1 + " WHERE " + cAlias + "." + cPK + "="
   cRet += cAl1 + "." + cPk

   If n = 0
      cRet += " AND " + cAl1 + ".DT__HIST <= " + SR_cDBValue(CurrDate)
   endif

   cRet += "))"

RETURN cRet

/*------------------------------------------------------------------------*/

FUNCTION SR_HistExpressionWhere(n, cTable, cPK, CurrDate, nSystem, cAlias)

   LOCAL cRet
   LOCAL cAl1
   LOCAL cAl2
   LOCAL oCnn

   oCnn := SR_GetConnection()

   cAl1   := "W" + StrZero(++_nCnt, 3)
   cAl2   := "W" + StrZero(++_nCnt, 3)

   If _nCnt >= 995
      _nCnt := 1
   EndIf

   DEFAULT CurrDate TO SR_GetActiveDt()
   DEFAULT n TO 0
   DEFAULT nSystem TO oCnn:nSystemID

   cRet := ""

   cRet += "(" + cAlias + ".DT__HIST = (SELECT" + iif(n = 3, " MIN(", " MAX(") + cAl1 + ".DT__HIST) FROM "
   cRet += cTable + " " + cAl1 + " WHERE " + cAlias + "." + cPK + "="
   cRet += cAl1 + "." + cPk

   If n = 0
      cRet += " AND " + cAl1 + ".DT__HIST <= " + SR_cDBValue(CurrDate)
   endif

   cRet += "))"

RETURN cRet

/*------------------------------------------------------------------------*/

FUNCTION SR_SetNextSvVers(lVers)

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):lVers := lVers
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_GetRddName(nArea)

   DEFAULT nArea TO Select()

   Do Case
   Case Empty(Alias(nArea))
      RETURN "    "
   OtherWise
      RETURN (nArea)->(RddName())
   EndCase

RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION IsSQLWorkarea()

RETURN "*" + SR_GetRddName() + "*" $ "*SQLRDD*ODBCRDD*SQLEX*"

/*------------------------------------------------------------------------*/

FUNCTION SR_OrdCondSet(cForSql, cForxBase)

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):OrdSetForClause(cForSql, cForxBase)
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_SetJoin(nAreaTarget, cField, nAlias, nOrderTarget)

   HB_SYMBOL_UNUSED(nAreaTarget)
   HB_SYMBOL_UNUSED(cField)
   HB_SYMBOL_UNUSED(nAlias)
   HB_SYMBOL_UNUSED(nOrderTarget)

   SR_RuntimeErr(, "SR_SetJoin() is no longer supported")

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_AddRuleNotNull(cCol)

   LOCAL lRet

   If IS_SQLRDD
      lRet := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):AddRuleNotNull(cCol)
      SR_CleanTabInfoCache()
      RETURN lRet
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_Deserialize(uData)

   //LOCAL ctemp
   //LOCAL cdes
   //LOCALchex

// cTemp := udata
// altd()
// cHex := SR_HEXTOSTR(SubStr(uData, 21, val(substr(uData, 11, 10))))
// cdes := sr_Deserialize1(cHex)
// tracelog(udata, chex, cdes)
// RETURN cdes

RETURN SR_Deserialize1(SR_HEXTOSTR(SubStr(uData, 21, val(substr(uData, 11, 10)))))

/*------------------------------------------------------------------------*/

FUNCTION SR_DropRuleNotNull(cCol)

   LOCAL lRet

   If IS_SQLRDD
      lRet := (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):DropRuleNotNull(cCol)
      SR_CleanTabInfoCache()
      RETURN lRet
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_LastSQLError()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):oSql:cSQLError
   EndIf

RETURN ""

/*------------------------------------------------------------------------*/

FUNCTION SR_SetFilter(cFlt)

   LOCAL oWA
   LOCAL uRet

   If IS_SQLRDD
      oWA := (Select())->(dbInfo(DBI_INTERNAL_OBJECT))
      uRet := oWA:cFilter
      If !Empty(cFlt)
         oWA:cFilter := cFlt
         oWA:Refresh()
      ElseIf HB_ISSTRING(cFlt) 
         oWA:cFilter := ""
      EndIf
   EndIf

RETURN uRet

/*------------------------------------------------------------------------*/

FUNCTION SR_ResetStatistics()

   If IS_SQLRDD
      (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):ResetStatistics()
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_GetnConnection()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT):oSql:nID )
   EndIf

RETURN 0

/*------------------------------------------------------------------------*/

FUNCTION SR_HasFilters()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):HasFilters()
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_dbRefresh()

   LOCAL oWA

   If IS_SQLRDD
      oWA := (Select())->(dbInfo(DBI_INTERNAL_OBJECT))
      oWA:Refresh()
      If !oWA:aInfo[AINFO_EOF]
         oWA:sqlGoTo(oWA:aInfo[AINFO_RECNO])
      Else
         oWA:sqlGoPhantom()
      EndIf
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

CLASS SqlFastHash

   DATA hHash, nPartSize

   METHOD New(nPartSize)
   METHOD Insert(uHashKey, xValue)
   METHOD Find(uHashKey, nIndex, nPart)    /* nIndex and nPart by ref */
   METHOD Delete(uHashKey)
   METHOD Update(uHashKey, uValue)
   METHOD UpdateIndex(nPos, nPart, uValue)
   METHOD Haeval(bExpr)
ENDCLASS

/*------------------------------------------------------------------------*/

METHOD Haeval(bExpr) CLASS SqlFastHash

RETURN Heval(::hHash, bExpr)

/*------------------------------------------------------------------------*/

METHOD New(nPartSize) CLASS SqlFastHash

   ::nPartSize := nPartSize
   ::hHash := {=>}
   If nPartSize != NIL
      HSetPartition(::hHash, nPartSize)
   EndIf

RETURN Self

/*------------------------------------------------------------------------*/

METHOD Insert(uHashKey, xValue) CLASS SqlFastHash

   If len(::hHash) > HASH_TABLE_SIZE
      ::hHash := { => }          /* Reset hash table */
      HB_GCALL(.T.)              /* Release memory blocks */
   EndIf

   ::hHash[uHashKey] := xValue

RETURN .T.

/*------------------------------------------------------------------------*/

METHOD Find(uHashKey, nIndex, nPart) CLASS SqlFastHash

   LOCAL aData

   nIndex := HGetPos(::hHash, uHashKey)

   If nIndex > 0
      aData := HGetValueAt(::hHash, nIndex)
   EndIf

   nPart := 1     /* Compatible with old version */

RETURN aData

/*------------------------------------------------------------------------*/

METHOD Delete(uHashKey) CLASS SqlFastHash

   LOCAL nIndex := 0

   nIndex := HGetPos(::hHash, uHashKey)

   If nIndex > 0
      HDelAt(::hHash, nIndex)
      RETURN .T.
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

METHOD Update(uHashKey, uValue) CLASS SqlFastHash

   LOCAL nIndex := 0

   nIndex := HGetPos(::hHash, uHashKey)

   If nIndex > 0
      HSetValueAt(::hHash, nIndex, uValue)
      RETURN .T.
   EndIf

RETURN .F.

/*------------------------------------------------------------------------*/

METHOD UpdateIndex(nPos, nPart, uValue) CLASS SqlFastHash
   /* nPart not used - Compatible with old version */
   HB_SYMBOL_UNUSED(nPart)
   HSetValueAt(::hHash, nPos, uValue)
RETURN .F.

/*------------------------------------------------------------------------*/

FUNCTION SR_BeginTransaction(nCnn)

   LOCAL oCnn

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      If oCnn:nTransacCount == 0       // Commit any changes BEFORE Begin Transaction
         oCnn:Commit()
      EndIf
      oCnn:nTransacCount ++

      If oCnn:nSystemID == SYSTEMID_CACHE
         oCnn:exec("START TRANSACTION %COMMITMODE EXPLICIT ISOLATION LEVEL READ COMMITTED")
//         oCnn:exec("START TRANSACTION %COMMITMODE EXPLICIT")
      EndIf

   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_CommitTransaction(nCnn)

   LOCAL oCnn

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      If (oCnn:nTransacCount - 1) == 0
         oCnn:Commit()
         oCnn:nTransacCount := 0
      ElseIf (oCnn:nTransacCount - 1) > 0
         oCnn:nTransacCount --
      EndIf
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_SetAppSite(nCnn, cSite)

   LOCAL oCnn
   LOCAL cOld

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      cOld := oCnn:cSite
      If cSite != NIL
         oCnn:cSite := cSite
      EndIf
   EndIf

RETURN cOld

/*------------------------------------------------------------------------*/

FUNCTION SR_SetConnectionLogChanges(nCnn, nOpt)

   LOCAL oCnn
   LOCAL nOld

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      nOld := oCnn:nLogMode
      If nOpt != NIL
         oCnn:nLogMode := nOpt
      EndIf
   EndIf

RETURN nOld

/*------------------------------------------------------------------------*/

FUNCTION SR_SetAppUser(nCnn, cUsername)

   LOCAL oCnn
   LOCAL cOld

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      cOld := oCnn:cAppUser
      If cUsername != NIL
         oCnn:cAppUser := cUsername
      EndIf
   EndIf

RETURN cOld

/*------------------------------------------------------------------------*/

FUNCTION SR_SetALockWait(nCnn, nSeconds)

   LOCAL oCnn
   LOCAL nOld

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      nOld := oCnn:nLockWaitTime
      oCnn:nLockWaitTime := nSeconds
   EndIf

RETURN nOld

/*------------------------------------------------------------------------*/

FUNCTION SR_RollBackTransaction(nCnn)

   LOCAL oCnn

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      If oCnn:nTransacCount >  0
         oCnn:nTransacCount := 0
         // Should CLEAN UP ALL workareas BEFORE issue the ROLLBACK
         _SR_ScanExecAll({ |y, x| (y), aeval(x, { |z| z:Refresh(.F.) }) })
         oCnn:RollBack()
      EndIf
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_TransactionCount(nCnn)

   LOCAL oCnn

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      RETURN oCnn:nTransacCount
   EndIf

RETURN 0

/*------------------------------------------------------------------------*/

FUNCTION SR_EndTransaction(nCnn)

   LOCAL oCnn

   If HB_ISOBJECT(nCnn)
      oCnn := nCnn
   Else
      oCnn := SR_GetConnection(nCnn)
   EndIf

   If oCnn != NIL
      If oCnn:nTransacCount >  0
         oCnn:Commit()
         oCnn:nTransacCount := 0
      EndIf
   EndIf

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION SR_RuntimeErr(cOperation, cErr)

   LOCAL oErr := ErrorNew()
   LOCAL cDescr

   DEFAULT cOperation TO "SQLRDD"
   DEFAULT cErr TO "RunTimeError"

   cDescr := alltrim(cErr)

   oErr:genCode       := 99
   oErr:CanDefault    := .F.
   oErr:Severity      := ES_ERROR
   oErr:CanRetry      := .T.
   oErr:CanSubstitute := .F.
   oErr:Description   := cDescr + " - RollBack executed."
   oErr:subSystem     := "SQLRDD"
   oErr:operation     := cOperation
   oErr:OsCode        := 0

   SR_LogFile("sqlerror.log", {cDescr})

   Throw(oErr)

RETURN NIL

/*------------------------------------------------------------------------*/

FUNCTION dbCount()

   If IS_SQLRDD
      RETURN (Select())->(dbInfo(DBI_INTERNAL_OBJECT)):KeyCount()
   EndIf

RETURN 0

/*------------------------------------------------------------------------*/

FUNCTION SR_GetStack()

   LOCAL i := 1
   LOCAL cErrorLog := ""

   DO WHILE (i < 70)
      If !Empty(ProcName(i))
         cErrorLog += SR_CRLF + Trim(ProcName(i)) + "     Linha : " + alltrim(str(ProcLine(i)))
      EndIf
      i++
   ENDDO

RETURN cErrorLog

/*------------------------------------------------------------------------*/

/*

Alert() copied as SQLBINDBYVAL() -> DEMO banner protection

*/

//#include "hbsetup.ch"
#include "box.ch"
#include "common.ch"
#include "inkey.ch"
#include "setcurs.ch"

/* TOFIX: Clipper defines a clipped window for Alert() [vszakats] */

/* NOTE: Clipper will return NIL if the first parameter is not a string, but
         this is not documented. This implementation converts the first
         parameter to a string if another type was passed. You can switch back
         to Clipper compatible mode by defining constant
         HB_C52_STRICT. [vszakats] */

/* NOTE: Clipper handles these buttons { "Ok", "", "Cancel" } in a buggy way.
         This is fixed. [vszakats] */

/* NOTE: nDelay parameter is a Harbour extension. */

#define INRANGE(xLo, xVal, xHi)       (xVal >= xLo .AND. xVal <= xHi)

FUNCTION SQLBINDBYVAL(xMessage, aOptions, cColorNorm, nDelay)

   LOCAL nChoice
   LOCAL aSay
   LOCAL nPos
   LOCAL nWidth
   LOCAL nOpWidth
   LOCAL nInitRow
   LOCAL nInitCol
   LOCAL nKey
   LOCAL aPos
   LOCAL nCurrent
   LOCAL aHotkey
   LOCAL aOptionsOK
   LOCAL cEval
   LOCAL cColorHigh

   LOCAL nOldRow
   LOCAL nOldCol
   LOCAL nOldCursor
   LOCAL cOldScreen

   LOCAL nOldDispCount
   LOCAL nCount
   LOCAL nLen
   LOCAL sCopy
   LOCAL lWhile

   LOCAL cColorStr
   LOCAL cColorPair1
   LOCAL cColorPair2
   LOCAL cColor11
   LOCAL cColor12
   LOCAL cColor21
   LOCAL cColor22
   LOCAL nCommaSep
   LOCAL nSlash

#ifdef HB_COMPAT_C53
   LOCAL nMRow
   LOCAL nMCol
#endif

   /* TOFIX: Clipper decides at runtime, whether the GT is linked in,
             if it is not, the console mode is choosen here. [vszakats] */
   LOCAL lConsole := .F.

#ifdef HB_C52_UNDOC

   DEFAULT s_lNoAlert TO hb_argCheck("NOALERT")

   IF s_lNoAlert
      RETURN NIL
   ENDIF

#endif

   aSay := {}

#ifdef HB_C52_STRICT

   IF !ISCHARACTER(xMessage)
      RETURN NIL
   ENDIF

   DO WHILE ( nPos := At(';', xMessage) ) != 0
      AAdd(aSay, Left(xMessage, nPos - 1))
      xMessage := SubStr(xMessage, nPos + 1)
   ENDDO
   AAdd(aSay, xMessage)

#else

   IF PCount() == 0
      RETURN NIL
   ENDIF

   IF ISARRAY(xMessage)

      FOR EACH cEval IN xMessage
         IF ISCHARACTER(cEval)
            AAdd(aSay, cEval)
         ENDIF
      NEXT

   ELSE

      SWITCH ValType(xMessage)
      CASE "C"
      CASE "M"
         EXIT
      CASE "N"
         xMessage := LTrim(Str(xMessage))
         EXIT
      CASE "D"
         xMessage := DToC(xMessage)
         EXIT
      CASE "T"
         xMessage := TToC(xMessage)
         EXIT
      CASE "L"
         xMessage := iif(xMessage, ".T.", ".F.")
         EXIT
      CASE "O"
         xMessage := xMessage:className + " Object"
         EXIT
      CASE "B"
         xMessage := "{||...}"
         EXIT
      OTHERWISE
         xMessage := "NIL"
      ENDSWITCH

      DO WHILE ( nPos := At(';', xMessage) ) != 0
         AAdd(aSay, Left(xMessage, nPos - 1))
         xMessage := SubStr(xMessage, nPos + 1)
      ENDDO
      AAdd(aSay, xMessage)

      FOR EACH xMessage IN aSay

         IF ( nLen := Len(xMessage) ) > 58
            FOR nPos := 58 TO 1 STEP -1
               IF xMessage[nPos] $ ( " " + Chr(9) )
                  EXIT
               ENDIF
            NEXT nPos

            IF nPos == 0
               nPos := 58
            ENDIF

            sCopy := xMessage
            aSay[HB_EnumIndex()] := RTrim(Left(xMessage, nPos))

            IF Len(aSay) == HB_EnumIndex()
               aAdd(aSay, SubStr(sCopy, nPos + 1))
            ELSE
               aIns(aSay, HB_EnumIndex() + 1, SubStr(sCopy, nPos + 1), .T.)
            ENDIF
        ENDIF
      NEXT

   ENDIF

#endif

   IF !ISARRAY(aOptions)
      aOptions := {}
   ENDIF

   IF !ISCHARACTER(cColorNorm) .OR. EMPTY(cColorNorm)
      cColorNorm := "W+/R" // first pair color (Box line and Text)
      cColorHigh := "W+/B" // second pair color (Options buttons)
   ELSE

      /* NOTE: Clipper Alert does not handle second color pair properly.
               If we inform the second color pair, xHarbour alert will consider it.
               if we not inform the second color pair, then xHarbour alert will behave
               like Clipper.  2004/Sep/16 - Eduardo Fernandes <modalsist> */

      cColor11 := cColor12 := cColor21 := cColor22 := ""

      cColorStr := alltrim(StrTran(cColorNorm, " ", ""))
      nCommaSep := At(",", cColorStr)

      if nCommaSep > 0 // exist more than one color pair.
         cColorPair1 := SubStr(cColorStr, 1, nCommaSep - 1)
         cColorPair2 := SubStr(cColorStr, nCommaSep + 1)
      else
         cColorPair1 := cColorStr
         cColorPair2 := ""
      endif

      nSlash := At("/", cColorPair1)

      if nSlash > 1
         cColor11 := SubStr(cColorPair1, 1, nSlash - 1)
         cColor12 := SubStr(cColorPair1, nSlash + 1)
      else
         cColor11 := cColorPair1
         cColor12 := "R"
      endif

      if ColorValid(cColor11) .AND. ColorValid(cColor12)

        // if color pair is passed in numeric format, then we need to convert for
        // letter format to avoid blinking in some circumstances.
        if IsDigit(cColor11)
           cColor11 := COLORLETTER(cColor11)
        endif

        cColorNorm := cColor11

        if !empty(cColor12)

            if IsDigit(cColor12)
               cColor12 := COLORLETTER(cColor12)
            endif

            cColorNorm := cColor11+"/"+cColor12

        endif

      else
         cColor11 := "W+"
         cColor12 := "R"
         cColorNorm := cColor11+"/"+cColor12
      endif


      // if second color pair exist, then xHarbour alert will handle properly.
      if !empty(cColorPair2)

         nSlash := At("/", cColorPair2)

         if nSlash > 1
            cColor21 := SubStr(cColorPair2, 1, nSlash - 1)
            cColor22 := SubStr(cColorPair2, nSlash + 1)
         else
            cColor21 := cColorPair2
            cColor22 := "B"
         endif

         if ColorValid(cColor21) .AND. ColorValid(cColor22)

            if IsDigit(cColor21)
               cColor21 := COLORLETTER(cColor21)
            endif

            cColorHigh := cColor21

            if !empty(cColor22)

                if IsDigit(cColor22)
                   cColor22 := COLORLETTER(cColor22)
                endif

                // extracting color attributes from background color.
                cColor22 := StrTran(cColor22, "+", "")
                cColor22 := StrTran(cColor22, "*", "")
                cColorHigh := cColor21+"/"+cColor22

            endif

         else
            cColorHigh := "W+/B"
         endif

      else // if does not exist the second color pair, xHarbour alert will behave like Clipper
         if empty(cColor11) .OR. empty(cColor12)
            cColor11 := "B"
            cColor12 := "W+"
         else
            cColor11 := StrTran(cColor11, "+", "")
            cColor11 := StrTran(cColor11, "*", "")
         endif
         cColorHigh := cColor12+"/"+cColor11
      endif

   ENDIF

   IF nDelay == NIL
      nDelay := 0
   ENDIF

   /* The longest line */
   nWidth := 0
   AEval(aSay, {| x | nWidth := Max(Len(x), nWidth) })

   /* Cleanup the button array */
   aOptionsOK := {}
   FOR EACH cEval IN aOptions
      IF ISCHARACTER(cEval) .AND. !Empty(cEval)
         AAdd(aOptionsOK, cEval)
      ENDIF
   NEXT

   IF Len(aOptionsOK) == 0
      aOptionsOK := { 'Ok' }
#ifdef HB_C52_STRICT
   /* NOTE: Clipper allows only four options [vszakats] */
   ELSEIF Len(aOptionsOK) > 4
      aSize(aOptionsOK, 4)
#endif
   ENDIF

   /* Total width of the botton line (the one with choices) */
   nOpWidth := 0
   AEval(aOptionsOK, {| x | nOpWidth += Len(x) + 4 })

   /* what's wider ? */
   nWidth := Max(nWidth + 2 + iif(Len(aSay) == 1, 4, 0), nOpWidth + 2)

   /* box coordinates */
   nInitRow := Int(((MaxRow() - (Len(aSay) + 4)) / 2) + .5)
   nInitCol := Int(((MaxCol() - (nWidth + 2)) / 2) + .5)

   /* detect prompts positions */
   aPos := {}
   aHotkey := {}
   nCurrent := nInitCol + Int((nWidth - nOpWidth) / 2) + 2
   AEval(aOptionsOK, {| x | AAdd(aPos, nCurrent), AAdd(aHotKey, Upper(Left(x, 1))), nCurrent += Len(x) + 4 })

   nChoice := 1

   IF lConsole

      nCount := Len(aSay)
      FOR EACH cEval IN aSay
         OutStd(cEval)
         IF HB_EnumIndex() < nCount
            OutStd(hb_OSNewLine())
         ENDIF
      NEXT

      OutStd(" (")
      nCount := Len(aOptionsOK)
      FOR EACH cEval IN aOptionsOK
         OutStd(cEval)
         IF HB_EnumIndex() < nCount
            OutStd(", ")
         ENDIF
      NEXT
      OutStd(") ")

      /* choice loop */
      lWhile := .T.
      DO WHILE lWhile

         nKey := Inkey(nDelay, INKEY_ALL)

         SWITCH nKey
         CASE 0
            lWhile := .F.
            EXIT
         CASE K_ESC
            nChoice := 0
            lWhile  := .F.
            EXIT
         OTHERWISE
            IF Upper(Chr(nKey)) $ aHotkey
               nChoice := aScan(aHotkey, {| x | x == Upper(Chr(nKey)) })
               lWhile  := .F.
            ENDIF
         ENDSWITCH

      ENDDO

      OutStd(Chr(nKey))

   ELSE

      /* PreExt */
      nCount := nOldDispCount := DispCount()

      DO WHILE nCount-- != 0
         DispEnd()
      ENDDO

      /* save status */
      nOldRow := Row()
      nOldCol := Col()
      nOldCursor := SetCursor(SC_NONE)
      cOldScreen := SaveScreen(nInitRow, nInitCol, nInitRow + Len(aSay) + 3, nInitCol + nWidth + 1)

      /* draw box */
      DispBox(nInitRow, nInitCol, nInitRow + Len(aSay) + 3, nInitCol + nWidth + 1, B_SINGLE + ' ', cColorNorm)

      FOR EACH cEval IN aSay
         DispOutAt(nInitRow + HB_EnumIndex(), nInitCol + 1 + Int(((nWidth - Len(cEval)) / 2) + .5), cEval, cColorNorm)
      NEXT

      /* choice loop */
      lWhile := .T.
      DO WHILE lWhile

         nCount := Len(aSay)
         FOR EACH cEval IN aOptionsOK
            DispOutAt(nInitRow + nCount + 2, aPos[HB_EnumIndex()], " " + cEval + " ", cColorNorm)
         NEXT
         DispOutAt(nInitRow + nCount + 2, aPos[nChoice], " " + aOptionsOK[nChoice] + " ", cColorHigh)

         nKey := Inkey(nDelay, INKEY_ALL)

         SWITCH nKey
         CASE K_ENTER
         CASE K_SPACE
         CASE 0
            lWhile := .F.
            EXIT
         CASE K_ESC
            nChoice := 0
            lWhile  := .F.
            EXIT
#ifdef HB_COMPAT_C53
         CASE K_LBUTTONDOWN
            nMRow  := MRow()
            nMCol  := MCol()
            nPos   := 0
            nCount := Len(aSay)
            FOR EACH cEval IN aOptionsOK
               IF nMRow == nInitRow + nCount + 2 .AND. ;
                  INRANGE(aPos[HB_EnumIndex()], nMCol, aPos[HB_EnumIndex()] + Len(cEval) + 2 - 1)
                  nPos := HB_EnumIndex()
                  EXIT
               ENDIF
            NEXT
            IF nPos > 0
               nChoice := nPos
               lWhile := .F.
            ENDIF
            EXIT
#endif
         CASE K_LEFT
         CASE K_SH_TAB
            IF Len(aOptionsOK) > 1
               nChoice--
               IF nChoice == 0
                  nChoice := Len(aOptionsOK)
               ENDIF
               nDelay := 0
            ENDIF
            EXIT
         CASE K_RIGHT
         CASE K_TAB
            IF Len(aOptionsOK) > 1
               nChoice++
               IF nChoice > Len(aOptionsOK)
                  nChoice := 1
               ENDIF
               nDelay := 0
            ENDIF
            EXIT
         OTHERWISE
            IF Upper(Chr(nKey)) $ aHotkey
               nChoice := aScan(aHotkey, {| x | x == Upper(Chr(nKey)) })
               lWhile  := .F.
            ENDIF
         ENDSWITCH

      ENDDO

      /* Restore status */
      RestScreen(nInitRow, nInitCol, nInitRow + Len(aSay) + 3, nInitCol + nWidth + 1, cOldScreen)
      SetCursor(nOldCursor)
      SetPos(nOldRow, nOldCol)

      /* PostExt */
      DO WHILE nOldDispCount-- != 0
         DispBegin()
      ENDDO

   ENDIF

RETURN nChoice

//-----------------------------------//
// 2004/Setp/15 - Eduardo Fernandes
// Convert number color format to character color format.
STATIC FUNCTION COLORLETTER(cColor)

   LOCAL nColor

  if !IsCharacter(cColor)
     cColor := ""
  endif

  cColor := StrTran(cColor, " ", "")
  cColor := StrTran(cColor, "*", "")
  cColor := StrTran(cColor, "+", "")

  nColor := Abs(Val(cColor))

  SWITCH nColor
  CASE 0  ; cColor := "N"   ; EXIT
  CASE 1  ; cColor := "B"   ; EXIT
  CASE 2  ; cColor := "G"   ; EXIT
  CASE 3  ; cColor := "BG"  ; EXIT
  CASE 4  ; cColor := "R"   ; EXIT
  CASE 5  ; cColor := "RB"  ; EXIT
  CASE 6  ; cColor := "GR"  ; EXIT
  CASE 7  ; cColor := "W"   ; EXIT
  CASE 8  ; cColor := "N+"  ; EXIT
  CASE 9  ; cColor := "B+"  ; EXIT
  CASE 10 ; cColor := "G+"  ; EXIT
  CASE 11 ; cColor := "BG+" ; EXIT
  CASE 12 ; cColor := "R+"  ; EXIT
  CASE 13 ; cColor := "RB+" ; EXIT
  CASE 14 ; cColor := "GR+" ; EXIT
  CASE 15 ; cColor := "W+"  ; EXIT
  OTHERWISE
     cColor := "W+" // 15 is the max.
  ENDSWITCH

RETURN ( cColor )

//-----------------------------------//
// 2004/Setp/15 - Eduardo Fernandes
// Test vality of the color string
STATIC FUNCTION COLORVALID(cColor)

   IF !IsCharacter(cColor)
      RETURN .F.
   ENDIF

   cColor := StrTran(cColor, " ", "")
   cColor := StrTran(cColor, "*", "")
   cColor := StrTran(cColor, "+", "")
   cColor := Upper(cColor)

   if cColor == "0"  .OR. ;
      cColor == "1"  .OR. ;
      cColor == "2"  .OR. ;
      cColor == "3"  .OR. ;
      cColor == "4"  .OR. ;
      cColor == "5"  .OR. ;
      cColor == "6"  .OR. ;
      cColor == "7"  .OR. ;
      cColor == "8"  .OR. ;
      cColor == "9"  .OR. ;
      cColor == "10" .OR. ;
      cColor == "11" .OR. ;
      cColor == "12" .OR. ;
      cColor == "13" .OR. ;
      cColor == "14" .OR. ;
      cColor == "15" .OR. ;
      cColor == "B"  .OR. ;
      cColor == "BG" .OR. ;
      cColor == "G"  .OR. ;
      cColor == "GR" .OR. ;
      cColor == "N"  .OR. ;
      cColor == "R"  .OR. ;
      cColor == "RB" .OR. ;
      cColor == "W"

      RETURN .T.

   ENDIF

RETURN .F.

#PRAGMA BEGINDUMP

#include "compat.h"

#include "hbapi.h"
#include "hbapifs.h"
#include "hbapiitm.h"

#ifndef HB_PATH_MAX
#define HB_PATH_MAX     264 /* with trailing 0 byte */
#endif

/* TODO: Xbase++ has an extension where the second parameter can specify
         the required attribute. */

HB_FUNC( SR_PHFILE )
{
   PHB_ITEM pFile = hb_param(1, HB_IT_STRING);
   hb_retl(( pFile && hb_itemGetCLen(pFile) < HB_PATH_MAX - 1 ) ? hb_spFile(hb_itemGetCPtr(pFile), NULL) : HB_FALSE);
}

#PRAGMA ENDDUMP

FUNCTION sr_AddToFilter(nRecNo)

   LOCAL oWA

   If IS_SQLRDD
      oWA := (Select())->(dbInfo(DBI_INTERNAL_OBJECT))
      
      If !Empty(oWA:cFilter)
         aadd(oWA:aRecnoFilter, nRecno)
         oWA:Refresh()
      EndIf
   EndIf

RETURN NIL

FUNCTION sr_clearFilter()

   LOCAL oWa

   If IS_SQLRDD
      oWA := (Select())->(dbInfo(DBI_INTERNAL_OBJECT))
      
      If !Empty(oWA:cFilter)
         oWA:aRecnoFilter := {} 
         oWA:Refresh()
      EndIf
   EndIf

RETURN NIL


FUNCTION SR_SetFieldDefault(cTable, cField, cDefault)

   LOCAL oCnn
   LOCAL cSql := "ALTER TABLE "+ cTable + " ALTER COLUMN " +cField +" SET DEFAULT "

   oCnn := SR_GetConnection()
   IF HB_ISNUMERIC(cDefault) 
      cSql += Alltrim(str(cDefault))
   ELSEIF HB_ISSTRING(cDefault)
      IF Empty(cDefault)
         cSql += "''"
      ELSE
         cSql += "'" + cDefault + "'"
      ENDIF
   ENDIF
   IF oCnn:nSystemId == SYSTEMID_POSTGR
      oCnn:exec(cSql, , .F.)
      oCnn:Commit()
   ENDIF
RETURN NIL

FUNCTION SR_Deserialize1(cSerial, nMaxLen, lRecursive, aObj, aHash, aArray, aBlock)
RETURN HB_Deserialize(cSerial, nMaxLen, lRecursive, aObj, aHash, aArray, aBlock)
