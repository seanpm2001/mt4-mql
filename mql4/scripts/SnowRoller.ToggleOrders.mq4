/**
 * SnowRoller.ToggleOrders
 *
 * Send a chart command to SnowRoller to toggle the order display.
 */
#include <stddefines.mqh>
int   __InitFlags[] = {INIT_NO_BARS_REQUIRED};
int __DeinitFlags[];
#include <core/script.mqh>
#include <stdfunctions.mqh>


/**
 * Main function
 *
 * @return int - error status
 */
int onStart() {
   // check chart for an active EA
   if (ObjectFind("EA.status") == 0) {
      SendChartCommand("EA.command", "orderdisplay");
   }
   else {
      PlaySoundEx("Windows Chord.wav");
      MessageBoxEx(ProgramName(), "No sequence found.", MB_ICONEXCLAMATION|MB_OK);
   }
   return(catch("onStart(1)"));
}
