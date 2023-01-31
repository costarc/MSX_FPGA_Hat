This version drives the DIR signal for U1 using a separate GPIO.
I thought this might be needed, but the revision 1.1, which drives botjh MSX BUSDIR and LVC245 DIR pin,
is working perfectly for all the designs I created so far.
I am keepig this version ready just in case I reall needs it in the future, but so far this change is unnecessary, and v1.1 is actually better because it free up one extra pin in the GPIO for other use.
