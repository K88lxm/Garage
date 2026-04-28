#property strict
#property version   "1.00"
#property description "XAUUSD Profit Collector for IC Markets - aggressive but risk controlled"

#include <Trade/Trade.mqh>

//==============================
// Inputs: General
//==============================
input long   MagicNumber                 = 20260428;
input string TradeComment                = "XAUUSD Profit Collector";
input string TradeSymbol                 = "XAUUSD";

input double FixedLot                    = 0.01;
input bool   AllowAutoLot                = false;
input double RiskPercent                 = 1.0;

input int    MaxOpenTrades               = 1;
input int    MaxOpenTradesAggressive     = 2;

//==============================
// Inputs: Session / Time
//==============================
input bool   UseSessionFilter            = true;
input int    LondonStartHourUK           = 7;
input int    LondonEndHourUK             = 11;
input int    NYStartHourUK               = 13;
input int    NYEndHourUK                 = 20;
input bool   AllowTradeAllDay            = false;
input bool   ManageOpenTradesOutsideSession = true;

input bool   AvoidRollover               = true;
input int    RolloverStartHourUK         = 22;
input int    RolloverEndHourUK           = 23;

//==============================
// Inputs: Indicator Filters
//==============================
input int    MaxSpreadPoints             = 50;

input bool   UseATRFilter                = true;
input int    ATRPeriod                   = 14;
input double MinATR                      = 0.20;

input bool   UseRSIFilter                = true;
input int    RSIPeriod                   = 14;
input double BuyRSILevel                 = 55.0;
input double SellRSILevel                = 45.0;

input int    M5FastEMA                   = 50;
input int    M5SlowEMA                   = 200;
input int    M1FastEMA                   = 20;
input int    M1SlowEMA                   = 50;

input bool   UseLiquiditySweepMode       = false;
input int    LiquidityLookbackBars       = 10;

//==============================
// Inputs: Profit & Trade Management
//==============================
input double ProfitTargetGBP             = 1.20;
input bool   UseAccountCurrencyProfitTarget = true;
input double BasketProfitTargetGBP       = 2.50;
input bool   UseBasketClose              = true;

input bool   UseVirtualMoneyTrail        = true;
input double TrailStartProfitGBP         = 0.40;
input double TrailDistanceGBP            = 0.30;
input double BreakEvenCloseGBP           = -0.20;
input double EmergencyStopLossGBP        = 3.00;

input bool   UseHardSL                   = true;
input int    HardSLPoints                = 1200;
input bool   UseHardTP                   = false;
input int    HardTPPoints                = 800;

//==============================
// Inputs: Daily Risk Control
//==============================
input double DailySoftTargetGBP          = 30.0;
input double DailyMainTargetGBP          = 50.0;
input double DailyMaxTargetGBP           = 100.0;
input double DailyMaxLossGBP             = 12.0;
input double DailyProfitGivebackGBP      = 7.50;

input bool   StopAtSoftTarget            = false;
input bool   ReduceRiskAfterSoftTarget   = true;
input bool   StopAtMainTarget            = false;
input bool   StopAtMaxTarget             = true;

//==============================
// Inputs: Shutdown
//==============================
input bool   UseDailyShutdown            = true;
input int    ShutdownHourUK              = 20;
input int    ShutdownMinuteUK            = 0;
input bool   StopNewTradesAfterShutdown  = true;
input bool   CloseProfitableTradesAtShutdown = true;
input bool   CloseBreakevenTradesAtShutdown  = true;
input double ShutdownBreakevenToleranceGBP = -0.30;
input bool   ForceCloseAllAtShutdown     = true;

//==============================
// Inputs: Frequency Control
//==============================
input bool   UseCooldown                 = true;
input int    CooldownSeconds             = 60;
input bool   OneTradePerCandle           = true;
input int    MaxTradesPerDay             = 100;
input int    MaxConsecutiveLosses        = 3;
input int    PauseAfterLossMinutes       = 10;

//==============================
// Inputs: Aggressive / Quality
//==============================
input bool   UseAggressiveMode           = true;
input bool   AggressiveAfterStrongTrend  = true;
input int    AggressiveMaxTrades         = 2;

input int    MinimumScoreToTrade         = 6;
input int    MinimumScoreProtectionMode  = 8;

//==============================
// Inputs: Equity Protection
//==============================
input bool   UseEquityProtection         = true;
input double MaxEquityDrawdownPercent    = 20.0;
input double MinEquityStopGBP            = 35.0;

//==============================
// Inputs: Push Mode
//==============================
input bool   UsePushMode                 = true;
input int    PushModeMinimumScore        = 8;
input bool   StopAfterPushModeGiveback   = true;

//==============================
// Globals
//==============================
CTrade trade;

int hM5FastEMA = INVALID_HANDLE;
int hM5SlowEMA = INVALID_HANDLE;
int hM1FastEMA = INVALID_HANDLE;
int hM1SlowEMA = INVALID_HANDLE;
int hM1RSI     = INVALID_HANDLE;
int hM1ATR     = INVALID_HANDLE;

enum TrendBias {BIAS_NEUTRAL = 0, BIAS_BULLISH = 1, BIAS_BEARISH = -1};
enum PhaseMode {MODE_BUILD = 0, MODE_PROTECTION = 1, MODE_PUSH = 2};

struct TrailState
{
   ulong ticket;
   double peakProfit;
   bool   active;
};

TrailState trailStates[];

string dashboardName = "XAUUSD_ProfitCollector_Dashboard";
string blockedReason = "";
string lastTradeResult = "N/A";

datetime lastTradeTime = 0;
datetime lastLossTime  = 0;
datetime lastTradeBarTime = 0;

bool tradingBlockedForDay = false;
int  blockedDayOfYear = -1;

double dayHighRealized = 0.0;
int consecutiveLosses = 0;

double startDayBalance = 0.0;
int startDayOfYear = -1;

//==============================
// Utility helpers
//==============================
int UKHourNow()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   return t.hour;
}

int UKMinuteNow()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   return t.min;
}

int UKDayOfYearNow()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);
   return t.day_of_year;
}

bool IsNewBar(const ENUM_TIMEFRAMES tf, datetime &lastBarStore)
{
   datetime curr = iTime(TradeSymbol, tf, 0);
   if(curr <= 0) return false;
   if(curr != lastBarStore)
   {
      lastBarStore = curr;
      return true;
   }
   return false;
}

double GetSpreadPoints()
{
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
   if(point <= 0.0) return 999999.0;
   return (ask - bid) / point;
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_STEP);

   lots = MathMax(minLot, MathMin(maxLot, lots));
   if(step > 0)
      lots = MathRound(lots / step) * step;

   int volDigits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_VOLUME_DIGITS);
   return NormalizeDouble(lots, volDigits);
}

double CalcLotSize()
{
   if(!AllowAutoLot)
      return NormalizeLots(FixedLot);

   // Conservative dynamic lot by risk percent using emergency stop monetary reference.
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = bal * (RiskPercent / 100.0);
   if(riskMoney <= 0.0 || EmergencyStopLossGBP <= 0.0)
      return NormalizeLots(FixedLot);

   double factor = riskMoney / EmergencyStopLossGBP;
   double lots = FixedLot * factor;
   return NormalizeLots(lots);
}

bool GetIndicatorValue(const int handle, const int shift, double &value)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) < 1)
      return false;
   value = buf[0];
   return true;
}

bool GetOHLC(const ENUM_TIMEFRAMES tf, const int shift, double &o, double &h, double &l, double &c)
{
   MqlRates rates[];
   if(CopyRates(TradeSymbol, tf, shift, 1, rates) < 1)
      return false;
   o = rates[0].open;
   h = rates[0].high;
   l = rates[0].low;
   c = rates[0].close;
   return true;
}

//==============================
// Daily stats and filters
//==============================
void ResetDailyStateIfNeeded()
{
   int dayNow = UKDayOfYearNow();
   if(startDayOfYear != dayNow)
   {
      startDayOfYear = dayNow;
      startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dayHighRealized = 0.0;
      consecutiveLosses = 0;

      if(blockedDayOfYear != dayNow)
         tradingBlockedForDay = false;
   }
}

double GetDailyProfit()
{
   ResetDailyStateIfNeeded();

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(dayStart, TimeCurrent()))
      return 0.0;

   double pnl = 0.0;
   int totalDeals = (int)HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(sym != TradeSymbol) continue;

      long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(magic != MagicNumber) continue;

      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;

      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      double comm   = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      double swap   = HistoryDealGetDouble(deal, DEAL_SWAP);
      pnl += (profit + comm + swap);
   }

   if(pnl > dayHighRealized)
      dayHighRealized = pnl;

   return pnl;
}

double GetFloatingProfit()
{
   double fp = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(sym == TradeSymbol && magic == MagicNumber)
         fp += PositionGetDouble(POSITION_PROFIT);
   }
   return fp;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == TradeSymbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         count++;
      }
   }
   return count;
}

bool ClosePositionByTicket(ulong ticket)
{
   if(ticket == 0) return false;
   if(!PositionSelectByTicket(ticket)) return false;

   if(PositionGetString(POSITION_SYMBOL) != TradeSymbol ||
      PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return false;

   if(!trade.PositionClose(ticket))
   {
      Print("Close failed for ticket ", ticket, " retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

void CloseAllEAOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(sym == TradeSymbol && magic == MagicNumber)
         ClosePositionByTicket(ticket);
   }
}

void RemoveTrailState(const ulong ticket)
{
   for(int i = ArraySize(trailStates) - 1; i >= 0; i--)
   {
      if(trailStates[i].ticket == ticket)
      {
         for(int j = i; j < ArraySize(trailStates) - 1; j++)
            trailStates[j] = trailStates[j + 1];
         ArrayResize(trailStates, ArraySize(trailStates) - 1);
         return;
      }
   }
}

int FindTrailState(const ulong ticket)
{
   for(int i = 0; i < ArraySize(trailStates); i++)
      if(trailStates[i].ticket == ticket)
         return i;
   return -1;
}

void EnsureTrailState(const ulong ticket)
{
   if(FindTrailState(ticket) >= 0) return;

   int sz = ArraySize(trailStates);
   ArrayResize(trailStates, sz + 1);
   trailStates[sz].ticket = ticket;
   trailStates[sz].peakProfit = -DBL_MAX;
   trailStates[sz].active = false;
}

bool CheckEquityProtection()
{
   if(!UseEquityProtection)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(equity <= MinEquityStopGBP)
   {
      blockedReason = "Equity below minimum stop";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      CloseAllEAOpenPositions();
      return true;
   }

   if(balance > 0.0)
   {
      double ddPct = ((balance - equity) / balance) * 100.0;
      if(ddPct >= MaxEquityDrawdownPercent)
      {
         blockedReason = "Equity drawdown protection triggered";
         tradingBlockedForDay = true;
         blockedDayOfYear = UKDayOfYearNow();
         CloseAllEAOpenPositions();
         return true;
      }
   }
   return false;
}

bool IsWithinTradingSession()
{
   if(AllowTradeAllDay)
      return true;

   int hour = UKHourNow();
   bool london = (hour >= LondonStartHourUK && hour < LondonEndHourUK);
   bool ny = (hour >= NYStartHourUK && hour < NYEndHourUK);
   return (london || ny);
}

bool IsRolloverTime()
{
   if(!AvoidRollover) return false;
   int hour = UKHourNow();
   return (hour >= RolloverStartHourUK && hour < RolloverEndHourUK);
}

bool IsShutdownTime()
{
   if(!UseDailyShutdown) return false;

   int h = UKHourNow();
   int m = UKMinuteNow();
   if(h > ShutdownHourUK) return true;
   if(h == ShutdownHourUK && m >= ShutdownMinuteUK) return true;
   return false;
}

void ApplyShutdownRules()
{
   if(!IsShutdownTime()) return;

   if(ForceCloseAllAtShutdown)
   {
      CloseAllEAOpenPositions();
      blockedReason = "Daily shutdown force close";
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double p = PositionGetDouble(POSITION_PROFIT);

      if(CloseProfitableTradesAtShutdown && p > 0.0)
      {
         ClosePositionByTicket(ticket);
         continue;
      }

      if(CloseBreakevenTradesAtShutdown && p >= ShutdownBreakevenToleranceGBP)
         ClosePositionByTicket(ticket);
   }
}

bool CheckDailyLimits()
{
   double dayProfit = GetDailyProfit();

   if(dayProfit <= -MathAbs(DailyMaxLossGBP))
   {
      blockedReason = "Daily max loss reached";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      CloseAllEAOpenPositions();
      return true;
   }

   if(dayProfit >= DailyMaxTargetGBP && StopAtMaxTarget)
   {
      blockedReason = "Daily max target reached";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      CloseAllEAOpenPositions();
      return true;
   }

   if(dayProfit >= DailyMainTargetGBP && StopAtMainTarget)
   {
      blockedReason = "Daily main target reached";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      return true;
   }

   if(dayProfit >= DailySoftTargetGBP && StopAtSoftTarget)
   {
      blockedReason = "Daily soft target reached";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      return true;
   }

   if(dayHighRealized - dayProfit >= DailyProfitGivebackGBP)
   {
      blockedReason = "Daily giveback limit reached";
      tradingBlockedForDay = true;
      blockedDayOfYear = UKDayOfYearNow();
      CloseAllEAOpenPositions();
      return true;
   }

   return false;
}

PhaseMode GetCurrentMode()
{
   double dayProfit = GetDailyProfit();

   if(dayProfit >= DailyMainTargetGBP && UsePushMode)
      return MODE_PUSH;

   if(dayProfit >= DailySoftTargetGBP && ReduceRiskAfterSoftTarget)
      return MODE_PROTECTION;

   return MODE_BUILD;
}

int CountTradesToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   if(!HistorySelect(dayStart, TimeCurrent()))
      return 0;

   int count = 0;
   int totalDeals = (int)HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(sym != TradeSymbol) continue;

      long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(magic != MagicNumber) continue;

      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(entry == DEAL_ENTRY_IN && (type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL))
         count++;
   }

   return count;
}

int CountConsecutiveLosses()
{
   if(!HistorySelect(0, TimeCurrent()))
      return consecutiveLosses;

   int losses = 0;
   int totalDeals = (int)HistoryDealsTotal();
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != TradeSymbol) continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber) continue;

      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(deal, DEAL_SWAP);

      if(pnl < 0)
      {
         losses++;
      }
      else
      {
         break;
      }
   }

   consecutiveLosses = losses;
   return losses;
}

//==============================
// Trend and setup
//==============================
TrendBias GetM5TrendBias()
{
   double emaFast, emaSlow;
   if(!GetIndicatorValue(hM5FastEMA, 1, emaFast) || !GetIndicatorValue(hM5SlowEMA, 1, emaSlow))
      return BIAS_NEUTRAL;

   double o, h, l, c;
   if(!GetOHLC(PERIOD_M5, 1, o, h, l, c))
      return BIAS_NEUTRAL;

   // Simple market structure check with last two highs/lows
   double prevHigh = iHigh(TradeSymbol, PERIOD_M5, 2);
   double prevLow  = iLow(TradeSymbol, PERIOD_M5, 2);
   double currHigh = iHigh(TradeSymbol, PERIOD_M5, 1);
   double currLow  = iLow(TradeSymbol, PERIOD_M5, 1);

   bool bullishStructure = (currHigh >= prevHigh && currLow >= prevLow);
   bool bearishStructure = (currHigh <= prevHigh && currLow <= prevLow);

   if(c > emaFast && emaFast > emaSlow && bullishStructure)
      return BIAS_BULLISH;

   if(c < emaFast && emaFast < emaSlow && bearishStructure)
      return BIAS_BEARISH;

   return BIAS_NEUTRAL;
}

bool ConfirmationCandleBullish()
{
   double o, h, l, c;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   double prevHigh = iHigh(TradeSymbol, PERIOD_M1, 2);
   return (c > o && c > prevHigh);
}

bool ConfirmationCandleBearish()
{
   double o, h, l, c;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   double prevLow = iLow(TradeSymbol, PERIOD_M1, 2);
   return (c < o && c < prevLow);
}

bool LiquiditySweepBuy()
{
   if(!UseLiquiditySweepMode) return false;

   int llShift = iLowest(TradeSymbol, PERIOD_M1, MODE_LOW, LiquidityLookbackBars, 2);
   if(llShift < 0) return false;

   double sweptLevel = iLow(TradeSymbol, PERIOD_M1, llShift);
   double o, h, l, c;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   double rsi;
   if(!GetIndicatorValue(hM1RSI, 1, rsi)) return false;

   TrendBias m5 = GetM5TrendBias();
   return (l < sweptLevel && c > sweptLevel && rsi > 50.0 && m5 != BIAS_BEARISH);
}

bool LiquiditySweepSell()
{
   if(!UseLiquiditySweepMode) return false;

   int hhShift = iHighest(TradeSymbol, PERIOD_M1, MODE_HIGH, LiquidityLookbackBars, 2);
   if(hhShift < 0) return false;

   double sweptLevel = iHigh(TradeSymbol, PERIOD_M1, hhShift);
   double o, h, l, c;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   double rsi;
   if(!GetIndicatorValue(hM1RSI, 1, rsi)) return false;

   TrendBias m5 = GetM5TrendBias();
   return (h > sweptLevel && c < sweptLevel && rsi < 50.0 && m5 != BIAS_BULLISH);
}

int GetMarketQualityScore(const bool forBuy)
{
   int score = 0;

   TrendBias m5 = GetM5TrendBias();
   if((forBuy && m5 == BIAS_BULLISH) || (!forBuy && m5 == BIAS_BEARISH))
      score += 2;

   double m1Fast, m1Slow;
   double o, h, l, c;
   if(GetIndicatorValue(hM1FastEMA, 1, m1Fast) && GetIndicatorValue(hM1SlowEMA, 1, m1Slow) && GetOHLC(PERIOD_M1, 1, o, h, l, c))
   {
      bool m1Aligned = (forBuy ? (c > m1Slow && m1Fast > m1Slow) : (c < m1Slow && m1Fast < m1Slow));
      if(m1Aligned) score += 2;
   }

   double rsi;
   if(GetIndicatorValue(hM1RSI, 1, rsi))
   {
      if((forBuy && rsi >= BuyRSILevel) || (!forBuy && rsi <= SellRSILevel))
         score += 1;
   }

   double atr;
   if(GetIndicatorValue(hM1ATR, 1, atr))
   {
      if(!UseATRFilter || atr >= MinATR)
         score += 1;
   }

   if(GetSpreadPoints() <= MaxSpreadPoints)
      score += 1;

   bool conf = forBuy ? ConfirmationCandleBullish() : ConfirmationCandleBearish();
   if(conf) score += 1;

   if(IsWithinTradingSession()) score += 1;

   return score;
}

bool CheckBuySetup()
{
   TrendBias m5 = GetM5TrendBias();
   if(m5 != BIAS_BULLISH) return false;

   double ema20, ema50, rsi, atr;
   double o, h, l, c;
   if(!GetIndicatorValue(hM1FastEMA, 1, ema20)) return false;
   if(!GetIndicatorValue(hM1SlowEMA, 1, ema50)) return false;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   bool pb = (MathAbs(c - ema20) <= (2 * _Point) || MathAbs(c - ema50) <= (4 * _Point));
   bool trend = (c > ema50);

   if(UseRSIFilter)
   {
      if(!GetIndicatorValue(hM1RSI, 1, rsi)) return false;
      if(rsi < BuyRSILevel) return false;
   }

   if(UseATRFilter)
   {
      if(!GetIndicatorValue(hM1ATR, 1, atr)) return false;
      if(atr < MinATR) return false;
   }

   if(GetSpreadPoints() > MaxSpreadPoints) return false;

   bool trigger = ConfirmationCandleBullish() || LiquiditySweepBuy();
   return trend && pb && trigger;
}

bool CheckSellSetup()
{
   TrendBias m5 = GetM5TrendBias();
   if(m5 != BIAS_BEARISH) return false;

   double ema20, ema50, rsi, atr;
   double o, h, l, c;
   if(!GetIndicatorValue(hM1FastEMA, 1, ema20)) return false;
   if(!GetIndicatorValue(hM1SlowEMA, 1, ema50)) return false;
   if(!GetOHLC(PERIOD_M1, 1, o, h, l, c)) return false;

   bool pb = (MathAbs(c - ema20) <= (2 * _Point) || MathAbs(c - ema50) <= (4 * _Point));
   bool trend = (c < ema50);

   if(UseRSIFilter)
   {
      if(!GetIndicatorValue(hM1RSI, 1, rsi)) return false;
      if(rsi > SellRSILevel) return false;
   }

   if(UseATRFilter)
   {
      if(!GetIndicatorValue(hM1ATR, 1, atr)) return false;
      if(atr < MinATR) return false;
   }

   if(GetSpreadPoints() > MaxSpreadPoints) return false;

   bool trigger = ConfirmationCandleBearish() || LiquiditySweepSell();
   return trend && pb && trigger;
}

bool OpenBuy()
{
   double lot = CalcLotSize();
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   if(ask <= 0) return false;

   double sl = 0.0, tp = 0.0;
   if(UseHardSL)
      sl = NormalizeDouble(ask - HardSLPoints * _Point, _Digits);
   if(UseHardTP)
      tp = NormalizeDouble(ask + HardTPPoints * _Point, _Digits);

   bool ok = trade.Buy(lot, TradeSymbol, ask, sl, tp, TradeComment);
   if(!ok)
   {
      Print("Buy failed retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
      return false;
   }

   lastTradeTime = TimeCurrent();
   lastTradeResult = "BUY opened";
   return true;
}

bool OpenSell()
{
   double lot = CalcLotSize();
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   if(bid <= 0) return false;

   double sl = 0.0, tp = 0.0;
   if(UseHardSL)
      sl = NormalizeDouble(bid + HardSLPoints * _Point, _Digits);
   if(UseHardTP)
      tp = NormalizeDouble(bid - HardTPPoints * _Point, _Digits);

   bool ok = trade.Sell(lot, TradeSymbol, bid, sl, tp, TradeComment);
   if(!ok)
   {
      Print("Sell failed retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
      return false;
   }

   lastTradeTime = TimeCurrent();
   lastTradeResult = "SELL opened";
   return true;
}

void CheckBasketProfit()
{
   if(!UseBasketClose) return;

   double floating = GetFloatingProfit();
   if(floating >= BasketProfitTargetGBP)
      CloseAllEAOpenPositions();
}

void ManageMoneyTrailing()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      EnsureTrailState(ticket);
      int idx = FindTrailState(ticket);
      if(idx < 0) continue;

      double p = PositionGetDouble(POSITION_PROFIT);

      if(p > trailStates[idx].peakProfit)
         trailStates[idx].peakProfit = p;

      if(p <= -MathAbs(EmergencyStopLossGBP))
      {
         lastTradeResult = "Closed: emergency money SL";
         ClosePositionByTicket(ticket);
         RemoveTrailState(ticket);
         continue;
      }

      if(p >= ProfitTargetGBP)
      {
         lastTradeResult = "Closed: profit target";
         ClosePositionByTicket(ticket);
         RemoveTrailState(ticket);
         continue;
      }

      if(!UseVirtualMoneyTrail) continue;

      if(p >= TrailStartProfitGBP)
         trailStates[idx].active = true;

      if(trailStates[idx].active)
      {
         double dynamicTrail = TrailDistanceGBP;
         if(GetCurrentMode() == MODE_PROTECTION)
            dynamicTrail = MathMax(0.10, TrailDistanceGBP * 0.8);

         if((trailStates[idx].peakProfit - p) >= dynamicTrail)
         {
            lastTradeResult = "Closed: trail pullback";
            ClosePositionByTicket(ticket);
            RemoveTrailState(ticket);
            continue;
         }

         if(p <= BreakEvenCloseGBP)
         {
            lastTradeResult = "Closed: BE protect";
            ClosePositionByTicket(ticket);
            RemoveTrailState(ticket);
            continue;
         }
      }
   }
}

void ManageOpenPositions()
{
   ManageMoneyTrailing();
   CheckBasketProfit();

   // Cleanup stale trailing states when position no longer exists
   for(int i = ArraySize(trailStates) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(trailStates[i].ticket))
         RemoveTrailState(trailStates[i].ticket);
   }
}

bool CheckTradingAllowed()
{
   blockedReason = "";

   ResetDailyStateIfNeeded();

   if(tradingBlockedForDay && blockedDayOfYear == UKDayOfYearNow())
   {
      blockedReason = "Blocked until next day";
      return false;
   }

   if(CheckDailyLimits())
      return false;

   if(CheckEquityProtection())
      return false;

   if(IsShutdownTime() && StopNewTradesAfterShutdown)
   {
      blockedReason = "Shutdown period";
      return false;
   }

   if(IsRolloverTime())
   {
      blockedReason = "Rollover blocked";
      return false;
   }

   if(UseSessionFilter && !AllowTradeAllDay && !IsWithinTradingSession())
   {
      blockedReason = "Outside trading session";
      return false;
   }

   if(UseCooldown && (TimeCurrent() - lastTradeTime) < CooldownSeconds)
   {
      blockedReason = "Cooldown active";
      return false;
   }

   if(MaxTradesPerDay > 0 && CountTradesToday() >= MaxTradesPerDay)
   {
      blockedReason = "Max trades/day reached";
      return false;
   }

   if(MaxConsecutiveLosses > 0)
   {
      int losses = CountConsecutiveLosses();
      if(losses >= MaxConsecutiveLosses)
      {
         if(lastLossTime == 0)
            lastLossTime = TimeCurrent();

         if((TimeCurrent() - lastLossTime) < (PauseAfterLossMinutes * 60))
         {
            blockedReason = "Paused after consecutive losses";
            return false;
         }
      }
      else
      {
         lastLossTime = 0;
      }
   }

   return true;
}

void UpdateDashboard()
{
   double dayProfit = GetDailyProfit();
   double floating = GetFloatingProfit();
   int spread = (int)MathRound(GetSpreadPoints());

   PhaseMode mode = GetCurrentMode();
   string modeStr = (mode == MODE_BUILD ? "Build" : (mode == MODE_PROTECTION ? "Protection" : "Push"));

   bool allowed = CheckTradingAllowed();
   int buyScore = GetMarketQualityScore(true);
   int sellScore = GetMarketQualityScore(false);
   int openTrades = CountOpenPositions();

   string sessionStr = IsWithinTradingSession() ? "Active (London/NY)" : "Inactive";
   string shutdownStr = IsShutdownTime() ? "Yes" : "No";

   string text;
   text = "EA: XAUUSD_ProfitCollector_ICM\n";
   text += "Symbol: " + TradeSymbol + "\n";
   text += "Spread(points): " + IntegerToString(spread) + "\n";
   text += "Session: " + sessionStr + "\n";
   text += "Trading allowed: " + (allowed ? "true" : "false") + "\n";
   text += "Blocked reason: " + (blockedReason == "" ? "None" : blockedReason) + "\n";
   text += "Daily realized P/L: " + DoubleToString(dayProfit, 2) + "\n";
   text += "Floating P/L: " + DoubleToString(floating, 2) + "\n";
   text += "Targets Soft/Main/Max: " + DoubleToString(DailySoftTargetGBP,2) + "/" + DoubleToString(DailyMainTargetGBP,2) + "/" + DoubleToString(DailyMaxTargetGBP,2) + "\n";
   text += "Daily loss limit: -" + DoubleToString(DailyMaxLossGBP,2) + "\n";
   text += "Mode: " + modeStr + "\n";
   text += "Push mode active: " + (mode == MODE_PUSH ? "true" : "false") + "\n";
   text += "Shutdown active: " + shutdownStr + "\n";
   text += "Open trades: " + IntegerToString(openTrades) + "\n";
   text += "Quality score Buy/Sell: " + IntegerToString(buyScore) + "/" + IntegerToString(sellScore) + "\n";
   text += "Consecutive losses: " + IntegerToString(consecutiveLosses) + "\n";
   text += "Last trade result: " + lastTradeResult;

   Comment(text);
}

//==============================
// MT5 lifecycle
//==============================
int OnInit()
{
   if(_Symbol != TradeSymbol)
      Print("Attach EA on chart symbol ", TradeSymbol, " for intended behavior.");

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   hM5FastEMA = iMA(TradeSymbol, PERIOD_M5, M5FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hM5SlowEMA = iMA(TradeSymbol, PERIOD_M5, M5SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hM1FastEMA = iMA(TradeSymbol, PERIOD_M1, M1FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hM1SlowEMA = iMA(TradeSymbol, PERIOD_M1, M1SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hM1RSI     = iRSI(TradeSymbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE);
   hM1ATR     = iATR(TradeSymbol, PERIOD_M1, ATRPeriod);

   if(hM5FastEMA == INVALID_HANDLE || hM5SlowEMA == INVALID_HANDLE ||
      hM1FastEMA == INVALID_HANDLE || hM1SlowEMA == INVALID_HANDLE ||
      hM1RSI == INVALID_HANDLE || hM1ATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles.");
      return INIT_FAILED;
   }

   ResetDailyStateIfNeeded();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hM5FastEMA != INVALID_HANDLE) IndicatorRelease(hM5FastEMA);
   if(hM5SlowEMA != INVALID_HANDLE) IndicatorRelease(hM5SlowEMA);
   if(hM1FastEMA != INVALID_HANDLE) IndicatorRelease(hM1FastEMA);
   if(hM1SlowEMA != INVALID_HANDLE) IndicatorRelease(hM1SlowEMA);
   if(hM1RSI     != INVALID_HANDLE) IndicatorRelease(hM1RSI);
   if(hM1ATR     != INVALID_HANDLE) IndicatorRelease(hM1ATR);

   Comment("");
}

void OnTick()
{
   // Priority: manage risk before entries.
   ResetDailyStateIfNeeded();

   // 1. Check daily max loss/limits
   CheckDailyLimits();

   // 2. Check equity protection
   CheckEquityProtection();

   // 3. Check daily shutdown and apply close logic
   ApplyShutdownRules();

   // 4/5/6/7. Manage emergency loss, per-trade target, virtual trailing, basket close
   ManageOpenPositions();

   // 8. Phase/target modes are handled in scoring and trade allowance checks.

   // 9. Only then evaluate new entries.
   bool allowNewEntries = CheckTradingAllowed();

   UpdateDashboard();

   if(!allowNewEntries)
      return;

   if(OneTradePerCandle)
   {
      datetime barTime = iTime(TradeSymbol, PERIOD_M1, 0);
      if(barTime == lastTradeBarTime)
         return;
   }

   int openCount = CountOpenPositions();
   PhaseMode mode = GetCurrentMode();

   int maxAllowed = MaxOpenTrades;
   if(mode == MODE_PROTECTION)
      maxAllowed = 1;
   else if(mode == MODE_PUSH && UsePushMode)
      maxAllowed = 1;
   else if(UseAggressiveMode && AggressiveAfterStrongTrend)
      maxAllowed = MathMin(MaxOpenTradesAggressive, AggressiveMaxTrades);

   if(openCount >= maxAllowed)
      return;

   bool canBuy = CheckBuySetup();
   bool canSell = CheckSellSetup();

   int buyScore = GetMarketQualityScore(true);
   int sellScore = GetMarketQualityScore(false);

   int minScore = MinimumScoreToTrade;
   if(mode == MODE_PROTECTION)
      minScore = MinimumScoreProtectionMode;
   if(mode == MODE_PUSH)
      minScore = MathMax(minScore, PushModeMinimumScore);

   bool opened = false;
   if(canBuy && buyScore >= minScore)
      opened = OpenBuy();
   else if(canSell && sellScore >= minScore)
      opened = OpenSell();

   if(opened)
      lastTradeBarTime = iTime(TradeSymbol, PERIOD_M1, 0);
}
