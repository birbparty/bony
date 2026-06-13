import bddy
import bony

spec "bony package":
  it "exposes version":
    then:
      bonyVersion == "0.1.0"
