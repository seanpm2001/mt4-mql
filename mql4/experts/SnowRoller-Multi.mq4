/**
 * SnowRoller-Strategy (Multi-Sequence-SnowRoller)
 */
#property stacksize 32768

#include <stddefine.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];
#include <stdlib.mqh>
//#include <history.mqh>
//#include <win32api.mqh>

#include <core/expert.mqh>
#include <SnowRoller/define.mqh>
#include <SnowRoller/functions.mqh>


///////////////////////////////////////////////////////////////////// Konfiguration /////////////////////////////////////////////////////////////////////

extern /*sticky*/ string StartConditions = "@trend(ALMA:3.5xD1)";    // @trend(ALMA:3.5xD1)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

string   last.StartConditions = "";                                  // Input-Parameter sind nicht statisch. Extern geladene Parameter werden bei REASON_CHARTCHANGE
                                                                     // mit den Default-Werten �berschrieben. Um dies zu verhindern und um neue mit vorherigen Werten
                                                                     // vergleichen zu k�nnen, werden sie in deinit() in diesen Variablen zwischengespeichert und in
                                                                     // init() wieder daraus restauriert.
bool     start.trend.condition;
string   start.trend.condition.txt;
double   start.trend.periods;
int      start.trend.timeframe, start.trend.timeframeFlag;           // maximal PERIOD_H1
string   start.trend.method;
int      start.trend.lag;


#include <SnowRoller/init.strategy.mqh>
#include <SnowRoller/deinit.strategy.mqh>


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   int signal;

   if (IsStartSignal(signal)) {
      if (signal > 0) {
         //debug("IsStartSignal()   D_LONG");
      }
      else            {
         //debug("IsStartSignal()   D_SHORT");
      }
   }
   return(catch("onTick()")|last_error);
}


/**
 * Signalgeber f�r Start einer neuen Sequence
 *
 * @param  int lpSignal - Zeiger auf Variable zur Signalaufnahme (+: Buy-Signal, -: Sell-Signal)
 *
 * @return bool - ob ein Signal aufgetreten ist
 */
bool IsStartSignal(int &lpSignal) {
   if (__STATUS_CANCELLED || __STATUS_ERROR)
      return(false);

   // -- start.trend: bei Trendwechsel erf�llt -----------------------------------------------------------------------
   if (start.trend.condition) {
      int iNull[];
      if (EventListener.BarOpen(iNull, start.trend.timeframeFlag)) {

         int    timeframe   = start.trend.timeframe;
         string maPeriods   = NumberToStr(start.trend.periods, ".+");
         string maTimeframe = PeriodDescription(start.trend.timeframe);
         string maMethod    = start.trend.method;
         int    lag         = start.trend.lag;
         int    bars        = start.trend.lag + 2 + 4;            // +2 (Bar 0 + Bar 3) und einige Bars mehr, um vorherrschenden Trend sicher zu bestimmen
         int    directions  = MODE_UPTREND | MODE_DOWNTREND;

         if (CheckTrendChange(timeframe, maPeriods, maTimeframe, maMethod, lag, bars, directions, lpSignal)) {
            if (!lpSignal)
               return(false);
            if (__LOG) log(StringConcatenate("IsStartSignal()   start condition \"", start.trend.condition.txt, "\" met"));
            return(true);
         }
      }
   }
   lpSignal = 0;
   return(false);
}


/**
 * Speichert die aktuelle Konfiguration zwischen, um sie bei Fehleingaben nach Parameter�nderungen restaurieren zu k�nnen.
 *
 * @return void
 */
void StoreConfiguration(bool save=true) {
   static string _StartConditions;

   static bool   _start.trend.condition;
   static string _start.trend.condition.txt;
   static double _start.trend.periods;
   static int    _start.trend.timeframe;
   static int    _start.trend.timeframeFlag;
   static string _start.trend.method;
   static int    _start.trend.lag;

   if (save) {
      _StartConditions           = StringConcatenate(StartConditions, "");  // Pointer-Bug bei String-Inputvariablen (siehe MQL.doc)

      _start.trend.condition     = start.trend.condition;
      _start.trend.condition.txt = start.trend.condition.txt;
      _start.trend.periods       = start.trend.periods;
      _start.trend.timeframe     = start.trend.timeframe;
      _start.trend.timeframeFlag = start.trend.timeframeFlag;
      _start.trend.method        = start.trend.method;
      _start.trend.lag           = start.trend.lag;
   }
   else {
      StartConditions            = _StartConditions;

      start.trend.condition      = _start.trend.condition;
      start.trend.condition.txt  = _start.trend.condition.txt;
      start.trend.periods        = _start.trend.periods;
      start.trend.timeframe      = _start.trend.timeframe;
      start.trend.timeframeFlag  = _start.trend.timeframeFlag;
      start.trend.method         = _start.trend.method;
      start.trend.lag            = _start.trend.lag;
   }
}


/**
 * Restauriert eine zuvor gespeicherte Konfiguration.
 *
 * @return void
 */
void RestoreConfiguration() {
   StoreConfiguration(false);
}


/**
 * Validiert die aktuelle Konfiguration.
 *
 * @param  bool interactive - ob fehlerhafte Parameter interaktiv korrigiert werden k�nnen
 *
 * @return bool - ob die Konfiguration g�ltig ist
 */
bool ValidateConfiguration(bool interactive) {
   if (__STATUS_ERROR)
      return(false);

   bool reasonParameters = (UninitializeReason() == REASON_PARAMETERS);
   if (reasonParameters)
      interactive = true;


   // (5) StartConditions, AND-verkn�pft: "(@trend(xxMA:7xD1[+2]"
   // ----------------------------------------------------------------------------------------------------------------------
   if (!reasonParameters || StartConditions!=last.StartConditions) {
      start.trend.condition = false;

      // (5.1) StartConditions in einzelne Ausdr�cke zerlegen
      string exprs[], expr, elems[], key, value;
      int    iValue, time, sizeOfElems, sizeOfExprs=Explode(StartConditions, "&&", exprs, NULL);
      double dValue;

      // (5.2) jeden Ausdruck parsen und validieren
      for (int i=0; i < sizeOfExprs; i++) {
         expr = StringToLower(StringTrim(exprs[i]));
         if (StringLen(expr) == 0) {
            if (sizeOfExprs > 1)                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(16)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            break;
         }
         if (StringGetChar(expr, 0) != '@')            return(_false(ValidateConfig.HandleError("ValidateConfiguration(17)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         if (Explode(expr, "(", elems, NULL) != 2)     return(_false(ValidateConfig.HandleError("ValidateConfiguration(18)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         if (!StringEndsWith(elems[1], ")"))           return(_false(ValidateConfig.HandleError("ValidateConfiguration(19)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
         key   = StringTrim(elems[0]);
         value = StringTrim(StringLeft(elems[1], -1));
         if (StringLen(value) == 0)                    return(_false(ValidateConfig.HandleError("ValidateConfiguration(20)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));

         if (key == "@trend") {
            if (start.trend.condition)                 return(_false(ValidateConfig.HandleError("ValidateConfiguration(21)", "Invalid StartConditions = \""+ StartConditions +"\" (multiple trend conditions)", interactive)));
            if (Explode(value, ":", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(24)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            key   = StringToUpper(StringTrim(elems[0]));
            value = StringToUpper(elems[1]);
            // key="ALMA"
            if      (key == "SMA" ) start.trend.method = key;
            else if (key == "EMA" ) start.trend.method = key;
            else if (key == "SMMA") start.trend.method = key;
            else if (key == "LWMA") start.trend.method = key;
            else if (key == "ALMA") start.trend.method = key;
            else                                       return(_false(ValidateConfig.HandleError("ValidateConfiguration(25)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            // value="7XD1[+2]"
            if (Explode(value, "+", elems, NULL) == 1) {
               start.trend.lag = 1;
            }
            else {
               value = StringTrim(elems[1]);
               if (!StringIsInteger(value))            return(_false(ValidateConfig.HandleError("ValidateConfiguration(26)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               start.trend.lag = StrToInteger(value);
               if (start.trend.lag == 0)               return(_false(ValidateConfig.HandleError("ValidateConfiguration(27)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               value = elems[0];
            }
            // value="7XD1"
            if (Explode(value, "X", elems, NULL) != 2) return(_false(ValidateConfig.HandleError("ValidateConfiguration(28)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            elems[1]              = StringTrim(elems[1]);
            start.trend.timeframe = PeriodToId(elems[1]);
            if (start.trend.timeframe == -1)           return(_false(ValidateConfig.HandleError("ValidateConfiguration(29)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            value = StringTrim(elems[0]);
            if (!StringIsNumeric(value))               return(_false(ValidateConfig.HandleError("ValidateConfiguration(30)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            dValue = StrToDouble(value);
            if (dValue <= 0)                           return(_false(ValidateConfig.HandleError("ValidateConfiguration(31)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            if (NE(MathModFix(dValue, 0.5), 0))        return(_false(ValidateConfig.HandleError("ValidateConfiguration(32)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
            elems[0] = NumberToStr(dValue, ".+");
            switch (start.trend.timeframe) {           // Timeframes > H1 auf H1 umrechnen, iCustom() soll unabh�ngig vom MA mit maximal PERIOD_H1 laufen
               case PERIOD_MN1:                        return(_false(ValidateConfig.HandleError("ValidateConfiguration(33)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
               case PERIOD_H4 : { dValue *=   4; start.trend.timeframe = PERIOD_H1; break; }
               case PERIOD_D1 : { dValue *=  24; start.trend.timeframe = PERIOD_H1; break; }
               case PERIOD_W1 : { dValue *= 120; start.trend.timeframe = PERIOD_H1; break; }
            }
            start.trend.periods       = NormalizeDouble(dValue, 1);
            start.trend.timeframeFlag = PeriodFlag(start.trend.timeframe);
            start.trend.condition     = true;
            start.trend.condition.txt = "@trend("+ start.trend.method +":"+ elems[0] +"x"+ elems[1] + ifString(start.trend.lag==1, "", "+"+ start.trend.lag) +")";
            exprs[i]                  = start.trend.condition.txt;
         }
         else                                          return(_false(ValidateConfig.HandleError("ValidateConfiguration(45)", "Invalid StartConditions = \""+ StartConditions +"\"", interactive)));
      }
      StartConditions = JoinStrings(exprs, " && ");
   }


   // (8) __STATUS_INVALID_INPUT zur�cksetzen
   if (interactive)
      __STATUS_INVALID_INPUT = false;

   return(!last_error|catch("ValidateConfiguration(77)"));
}


/**
 * Exception-Handler f�r ung�ltige Input-Parameter. Je nach Situation wird der Fehler weitergereicht oder zur Korrektur aufgefordert.
 *
 * @param  string location    - Ort, an dem der Fehler auftrat
 * @param  string message     - Fehlermeldung
 * @param  bool   interactive - ob der Fehler interaktiv behandelt werden kann
 *
 * @return int - der resultierende Fehlerstatus
 */
int ValidateConfig.HandleError(string location, string message, bool interactive) {
   if (IsTesting())
      interactive = false;
   if (!interactive)
      return(catch(location +"   "+ message, ERR_INVALID_CONFIG_PARAMVALUE));

   if (__LOG) log(StringConcatenate(location, "   ", message), ERR_INVALID_INPUT);
   ForceSound("chord.wav");
   int button = ForceMessageBox(__NAME__ +" - "+ location, message, MB_ICONERROR|MB_RETRYCANCEL);

   __STATUS_INVALID_INPUT = true;

   if (button == IDRETRY)
      __STATUS_RELAUNCH_INPUT = true;

   return(NO_ERROR);
}


/**
 * Speichert die Konfiguartionsdaten des EA's im Chart, soda� der Status nach einem Recompile oder Terminal-Restart daraus wiederhergestellt werden kann.
 * Diese Werte umfassen die Input-Parameter sowie die Flags __STATUS_INVALID_INPUT und __STATUS_CANCELLED.
 *
 * @return int - Fehlerstatus
 */
int StoreStickyStatus() {
   string label = StringConcatenate(__NAME__, ".sticky.StartConditions");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StartConditions, 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS_INVALID_INPUT), 1);

   label = StringConcatenate(__NAME__, ".sticky.__STATUS_CANCELLED");
   if (ObjectFind(label) == 0)
      ObjectDelete(label);
   ObjectCreate (label, OBJ_LABEL, 0, 0, 0);
   ObjectSet    (label, OBJPROP_TIMEFRAMES, EMPTY);                           // hidden on all timeframes
   ObjectSetText(label, StringConcatenate("", __STATUS_CANCELLED), 1);

   return(catch("StoreStickyStatus()"));
}


/**
 * Restauriert die im Chart gespeicherten Konfigurationsdaten.
 *
 * @return bool - ob gespeicherte Daten gefunden wurden
 */
bool RestoreStickyStatus() {
   string label, strValue;
   bool   statusFound;

   label = StringConcatenate(__NAME__, ".sticky.StartConditions");
   if (ObjectFind(label) == 0) {
      StartConditions = StringTrim(ObjectDescription(label));
      statusFound     = true;

      label = StringConcatenate(__NAME__, ".sticky.__STATUS_INVALID_INPUT");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(1)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS_INVALID_INPUT = StrToInteger(strValue) != 0;
      }

      label = StringConcatenate(__NAME__, ".sticky.__STATUS_CANCELLED");
      if (ObjectFind(label) == 0) {
         strValue = StringTrim(ObjectDescription(label));
         if (!StringIsDigit(strValue))
            return(_false(catch("RestoreStickyStatus(2)   illegal chart value "+ label +" = \""+ ObjectDescription(label) +"\"", ERR_INVALID_CONFIG_PARAMVALUE)));
         __STATUS_CANCELLED = StrToInteger(strValue) != 0;
      }
   }

   return(statusFound && IsNoError(last_error|catch("RestoreStickyStatus(3)")));
}


/**
 * L�scht alle im Chart gespeicherten Konfigurationsdaten.
 *
 * @return int - Fehlerstatus
 */
int ClearStickyStatus() {
   string label, prefix=StringConcatenate(__NAME__, ".sticky.");

   for (int i=ObjectsTotal()-1; i>=0; i--) {
      label = ObjectName(i);
      if (StringStartsWith(label, prefix)) /*&&*/ if (ObjectFind(label) == 0)
         ObjectDelete(label);
   }
   return(catch("ClearStickyStatus()"));
}


/**
 * Unterdr�ckt unn�tze Compilerwarnungen.
 */
void DummyCalls() {
   string sNulls[];
   int    iNulls[];
   FindChartSequences(sNulls, iNulls);
}
