from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    # s.loadTopo("circle.topo");
    # s.loadTopo("house.topo");
    # s.loadTopo("pizza.topo");
    s.loadTopo("tuna-melt.topo");


    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");
    # s.loadNoise("some_noise.txt");
    # s.loadNoise("meyer-heavy.txt");


    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    # s.addChannel(s.NEIGHBOR_CHANNEL);
    # s.addChannel(s.FLOODING_CHANNEL);
    # s.addChannel(s.ROUTING_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(300);
    # s.routeDMP(1);
    # s.runTime(1);
    # s.ping(1, 10, "abcdefghijklmnopqrst");
    # s.runTime(50);

    # s.testServer(1);
    # s.routeDMP(10);
    # s.runTime(1);

    # s.testClient(4);
    # s.routeDMP(5);
    # s.runTime(1);

    s.cmdTestServer(1, 41);
    s.runTime(10);

    s.greet(1, 7, 22, 4, "jack");
    s.runTime(10);

    s.broadcastMsg(7, 11, "hello world");
    s.runTime(2);

    # s.unicastMsg(7, 4, "jack", 5, "hello");
    # s.runTime(2);

    # s.printAllUser(8);
    # s.runTime(2);

    s.runTime(300);

if __name__ == '__main__':
    main()
