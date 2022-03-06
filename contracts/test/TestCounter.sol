// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

//sample "receiver" contract, for testing "exec" from wallet.
contract TestCounter {
    mapping(address => uint) public counters;

    function count() public {
        counters[msg.sender] = counters[msg.sender] + 1;

    }

    function justemit() public {
        emit CalledFrom(msg.sender);
    }

    event CalledFrom(address sender);

    //helper method to waste gas
    // repeat - waste gas on writing storage in a loop
    // junk - dynamic buffer to stress the function size.
    mapping(uint => uint) xxx;
    uint offset;

    function gasWaster(uint repeat, string calldata /*junk*/) external {
        for (uint i = 1; i <= repeat; i++) {
            offset++;
            xxx[offset] = i;
        }
    }
}