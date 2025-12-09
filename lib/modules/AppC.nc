configuration AppC {
   provides interface App;
}

implementation {
    components AppP;
    App = AppP;

    components TransportC;
    AppP.Transport -> TransportC;
}