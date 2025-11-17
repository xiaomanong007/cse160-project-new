from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    # s.loadTopo("long_line.topo");
    s.loadTopo("tuna-melt.topo");


    # Add a noise model to all of the motes.
    # s.loadNoise("no_noise.txt");
    s.loadNoise("some_noise.txt");
    # s.loadNoise("meyer-heavy.txt");


    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(1);
    s.ping(1, 7, "Hello, World 1");
    s.runTime(1);

    s.ping(1, 7, "Hello, World 2");
    s.runTime(1);

    s.ping(1, 15, "Hello, World 3");
    s.runTime(1);

    s.ping(1, 15, "Hello, World 4");
    s.runTime(1);

    s.ping(1, 15, "Hello, World 5");
    s.runTime(1);

    s.ping(1, 7, "Hello, World 6");
    s.runTime(1);

    s.ping(1, 7, "Hello, World 7");
    s.runTime(1);

    s.ping(1, 7, "Hello, World 8");
    s.runTime(1);

    # s.ping(1, 10, "Hi!");
    # s.runTime(1);

if __name__ == '__main__':
    main()
