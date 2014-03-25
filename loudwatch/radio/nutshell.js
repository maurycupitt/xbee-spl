/**
 * Created by maurycupitt on 3/25/14.
 */
var util = require('util');
var XBee = require('./node_modules/svd-xbee/index.js').XBee;

var xbee = new XBee({
    port: '/dev/tty.usbserial-A601F1P2',
    //port: '/dev/tty.usbserial-A601F1U4',
    baudrate: 9600 // 9600 is default
}).init();



xbee.on("initialized", function(params) {
    console.log("XBee Parameters: %s", util.inspect(params));

    xbee.discover();
    console.log("Node discovery starded...");
});

xbee.on("discoveryEnd", function() {
    console.log("...node discovery over");
});

var robot = xbee.addNode([0x00, 0x13, 0xA2, 0x00, 0x40, 0xA2, 0x64, 0x7D]);


robot.on("data", function(data) {
    console.log("robot>", data);
    if (data == "ping") robot.send("pong");
});
