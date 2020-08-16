/**
 * Keltner Channel - an ATR channel around a Moving Average
 *
 * Upper and lower channel band are defined as:
 *  UpperBand = MA + ATR * Multiplier
 *  LowerBand = MA - ATR * Multiplier
 *
 * Supported Moving-Averages:
 *  � SMA  - Simple Moving Average:          equal bar weighting
 *  � LWMA - Linear Weighted Moving Average: bar weighting using a linear function
 *  � EMA  - Exponential Moving Average:     bar weighting using an exponential function
 *  � SMMA - Smoothed Moving Average:        same as EMA, it holds: SMMA(n) = EMA(2*n-1)
 *  � ALMA - Arnaud Legoux Moving Average:   bar weighting using a Gaussian function
 */
#include <stddefines.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern string ATR.Timeframe   = "current* | M1 | M5 | M15 | ..."; // empty: current
extern int    ATR.Periods     = 60;
extern double ATR.Multiplier  = 1;

extern string MA.Method       = "SMA* | LWMA | EMA | ALMA";
extern int    MA.Periods      = 10;
extern string MA.AppliedPrice = "Open | High | Low | Close* | Median | Typical | Weighted";

extern color  Color.Bands     = Blue;
extern color  Color.MA        = CLR_NONE;

extern int    Max.Bars        = 10000;                            // max. number of bars to display (-1: all available)

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <rsfLibs.mqh>
#include <functions/@ALMA.mqh>
#include <functions/@Bands.mqh>

#define MODE_MA               Bands.MODE_MA                       // indicator buffer ids
#define MODE_UPPER            Bands.MODE_UPPER
#define MODE_LOWER            Bands.MODE_LOWER

#property indicator_chart_window
#property indicator_buffers   3

#property indicator_style1    STYLE_DOT
#property indicator_style2    STYLE_SOLID
#property indicator_style3    STYLE_SOLID


double ma       [];
double upperBand[];
double lowerBand[];

int    atrTimeframe;
int    atrPeriods;
double atrMultiplier;

int    maMethod;
int    maPeriods;
int    maAppliedPrice;
double almaWeights[];                                             // ALMA bar weights

int    maxValues;

string indicatorName;
string legendLabel;


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   // validate inputs
   // ATR
   string sValues[], sValue = ATR.Timeframe;
   if (Explode(sValue, "*", sValues, 2) > 1) {
      int size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   sValue = StrTrim(sValue);
   if (sValue=="" || sValue=="0" || sValue=="current") {
      atrTimeframe  = Period();
      ATR.Timeframe = "current";
   }
   else {
      atrTimeframe = StrToTimeframe(sValue, F_ERR_INVALID_PARAMETER);
      if (atrTimeframe == -1) return(catch("onInit(1)  Invalid input parameter ATR.Timeframe: "+ DoubleQuoteStr(ATR.Timeframe), ERR_INVALID_INPUT_PARAMETER));
      ATR.Timeframe = TimeframeDescription(atrTimeframe);
   }
   if (ATR.Periods < 1)       return(catch("onInit(2)  Invalid input parameter ATR.Periods: "+ ATR.Periods, ERR_INVALID_INPUT_PARAMETER));
   if (ATR.Multiplier < 0)    return(catch("onInit(3)  Invalid input parameter ATR.Multiplier: "+ NumberToStr(ATR.Multiplier, ".+"), ERR_INVALID_INPUT_PARAMETER));
   atrPeriods    = ATR.Periods;
   atrMultiplier = ATR.Multiplier;
   // MA.Method
   sValue = MA.Method;
   if (Explode(sValue, "*", sValues, 2) > 1) {
      size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   sValue = StrTrim(sValue);
   maMethod = StrToMaMethod(sValue, F_ERR_INVALID_PARAMETER);
   if (maMethod == -1)        return(catch("onInit(4)  Invalid input parameter MA.Method: "+ DoubleQuoteStr(MA.Method), ERR_INVALID_INPUT_PARAMETER));
   MA.Method = MaMethodDescription(maMethod);
   // MA.Periods
   if (MA.Periods < 0)        return(catch("onInit(5)  Invalid input parameter MA.Periods: "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   maPeriods = ifInt(!MA.Periods, 1, MA.Periods);
   // MA.AppliedPrice
   sValue = StrToLower(MA.AppliedPrice);
   if (Explode(sValue, "*", sValues, 2) > 1) {
      size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   sValue = StrTrim(sValue);
   if (sValue == "") sValue = "close";                            // default price type
   maAppliedPrice = StrToPriceType(sValue, F_ERR_INVALID_PARAMETER);
   if (maAppliedPrice == -1) {
      if      (StrStartsWith("open",     sValue)) maAppliedPrice = PRICE_OPEN;
      else if (StrStartsWith("high",     sValue)) maAppliedPrice = PRICE_HIGH;
      else if (StrStartsWith("low",      sValue)) maAppliedPrice = PRICE_LOW;
      else if (StrStartsWith("close",    sValue)) maAppliedPrice = PRICE_CLOSE;
      else if (StrStartsWith("median",   sValue)) maAppliedPrice = PRICE_MEDIAN;
      else if (StrStartsWith("typical",  sValue)) maAppliedPrice = PRICE_TYPICAL;
      else if (StrStartsWith("weighted", sValue)) maAppliedPrice = PRICE_WEIGHTED;
      else                    return(catch("onInit(6)  Invalid input parameter MA.AppliedPrice: "+ DoubleQuoteStr(MA.AppliedPrice), ERR_INVALID_INPUT_PARAMETER));
   }
   MA.AppliedPrice = PriceTypeDescription(maAppliedPrice);

   // colors: after deserialization the terminal might turn CLR_NONE (0xFFFFFFFF) into Black (0xFF000000)
   if (Color.Bands == 0xFF000000) Color.Bands = CLR_NONE;
   if (Color.MA    == 0xFF000000) Color.MA    = CLR_NONE;

   // Max.Bars
   if (Max.Bars < -1)         return(catch("onInit(7)  Invalid input parameter Max.Bars: "+ Max.Bars, ERR_INVALID_INPUT_PARAMETER));
   maxValues = ifInt(Max.Bars==-1, INT_MAX, Max.Bars);

   // buffer management
   SetIndexBuffer(MODE_MA,    ma       );
   SetIndexBuffer(MODE_UPPER, upperBand);
   SetIndexBuffer(MODE_LOWER, lowerBand);

   // chart legend
   if (!IsSuperContext()) {
      legendLabel = CreateLegendLabel();
      RegisterObject(legendLabel);
   }

   // names, labels and display options
   string sMa            = MA.Method +"("+ maPeriods +")";
   string sAtrMultiplier = ifString(atrMultiplier==1, "", NumberToStr(atrMultiplier, ".+") +"*");
   string sAtrTimeframe  = ifString(ATR.Timeframe=="current", "", "x"+ ATR.Timeframe);
   string sAtr           = sAtrMultiplier +"ATR("+ atrPeriods + sAtrTimeframe +")";
   indicatorName         = "Keltner Channel "+ sMa +" � "+ sAtr;
   IndicatorShortName(indicatorName);                 // chart context menu
   SetIndexLabel(MODE_MA,    "Keltner Channel MA"); if (Color.MA == CLR_NONE) SetIndexLabel(MODE_MA, NULL);
   SetIndexLabel(MODE_UPPER, "Keltner Upper Band");   // chart tooltips and "Data" window
   SetIndexLabel(MODE_LOWER, "Keltner Lower Band");

   IndicatorDigits(Digits);
   SetIndicatorOptions();

   // pre-calculate ALMA bar weights
   if (maMethod == MODE_ALMA) @ALMA.CalculateWeights(almaWeights, maPeriods);

   return(catch("onInit(8)"));
}


/**
 * Deinitialization
 *
 * @return int - error status
 */
int onDeinit() {
   RepositionLegend();
   return(catch("onDeinit(1)"));
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   // under undefined conditions on the first tick after terminal start buffers may not yet be initialized
   if (!ArraySize(ma)) return(log("onTick(1)  size(ma) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // reset all buffers and delete garbage behind Max.Bars before doing a full recalculation
   if (!UnchangedBars) {
      ArrayInitialize(ma,        EMPTY_VALUE);
      ArrayInitialize(upperBand, EMPTY_VALUE);
      ArrayInitialize(lowerBand, EMPTY_VALUE);
      SetIndicatorOptions();
   }

   // synchronize buffers with a shifted offline chart
   if (ShiftedBars > 0) {
      ShiftIndicatorBuffer(ma,        Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(upperBand, Bars, ShiftedBars, EMPTY_VALUE);
      ShiftIndicatorBuffer(lowerBand, Bars, ShiftedBars, EMPTY_VALUE);
   }

   // calculate start bar
   int changedBars = Min(ChangedBars, maxValues);
   int startBar = Min(changedBars, Bars-maPeriods+1) - 1;
   if (startBar < 0) return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));

   // recalculate changed bars
   if (maMethod == MODE_ALMA) {
      RecalcALMAChannel(startBar);
   }
   else {
      for (int bar=startBar; bar >= 0; bar--) {
         double atr = iATR(NULL, atrTimeframe, atrPeriods, bar) * atrMultiplier;

         ma       [bar] = iMA(NULL, NULL, maPeriods, 0, maMethod, maAppliedPrice, bar);
         upperBand[bar] = ma[bar] + atr;
         lowerBand[bar] = ma[bar] - atr;
      }
   }
   @Bands.UpdateLegend(legendLabel, indicatorName, "", Color.Bands, upperBand[0], lowerBand[0], Digits, Time[0]);

   return(last_error);
}


/**
 * Recalculate the changed bars of an ALMA based Keltner Channel.
 *
 * @param  int startBar
 *
 * @return bool - success status
 */
bool RecalcALMAChannel(int startBar) {
   for (int i, j, bar=startBar; bar >= 0; bar--) {
      double atr = iATR(NULL, atrTimeframe, atrPeriods, bar) * atrMultiplier;

      ma[bar] = 0;
      for (i=0; i < maPeriods; i++) {
         ma[bar] += almaWeights[i] * iMA(NULL, NULL, 1, 0, MODE_SMA, maAppliedPrice, bar+i);
      }
      upperBand[bar] = ma[bar] + atr;
      lowerBand[bar] = ma[bar] - atr;
   }
   return(!catch("RecalcALMAChannel(1)"));
}


/**
 * Workaround for various terminal bugs when setting indicator options. Usually options are set in init(). However after
 * recompilation options must be set in start() to not be ignored.
 */
void SetIndicatorOptions() {
   int drawType = ifInt(Color.MA==CLR_NONE, DRAW_NONE, DRAW_LINE);

   SetIndexStyle(MODE_MA,    drawType,  EMPTY, EMPTY, Color.MA   );
   SetIndexStyle(MODE_UPPER, DRAW_LINE, EMPTY, EMPTY, Color.Bands);
   SetIndexStyle(MODE_LOWER, DRAW_LINE, EMPTY, EMPTY, Color.Bands);
}


/**
 * Return a string representation of the input parameters (for logging purposes).
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate(
                            "ATR.Timeframe=",   DoubleQuoteStr(ATR.Timeframe),      ";", NL,
                            "ATR.Periods=",     ATR.Periods,                        ";", NL,
                            "ATR.Multiplier=",  NumberToStr(ATR.Multiplier, ".1+"), ";", NL,
                            "MA.Method=",       DoubleQuoteStr(MA.Method),          ";", NL,
                            "MA.Periods=",      MA.Periods,                         ";", NL,
                            "MA.AppliedPrice=", DoubleQuoteStr(MA.AppliedPrice),    ";", NL,
                            "Color.Bands=",     ColorToStr(Color.Bands),            ";", NL,
                            "Color.MA=",        ColorToStr(Color.MA),               ";", NL,
                            "Max.Bars=",        Max.Bars,                           ";")
   );
}
