configuration AppC {
   provides interface App;
}

implementation {
    components AppP;
    App = AppP;

    components TransportC;
    AppP.Transport -> TransportC;

    components IPC;
    AppP.IP -> IPC;


    components new ListC(storedPkt_t, 20) as GreetQueue;
    AppP.GreetQueue -> GreetQueue;

    components new TimerMilliC() as GreetTimer;
    AppP.GreetTimer -> GreetTimer;
}