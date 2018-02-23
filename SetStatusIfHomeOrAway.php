<?php
//=============================================================================================
// Version                1.0
// Created by:            Marcus Opel
// Organization:          https://devmarc.de
// requires:              PHP 5.4 or higher
//=============================================================================================
date_default_timezone_set('Europe/Berlin');

function logToFile($msg)
{
    // open file
    $fh = fopen(str_replace(".php", ".log",__FILE__), "a");
    // append date/time to message
    $str = "[" . date('Y-m-d H:i:s') . "] " . $msg;
    // write string
    fwrite($fh, $str . "\n");
    // close file
    fclose($fh);
}

// set your vars
$statusFile = 'status.txt';
$secret = '123456789'; // must contain secret, used in IFTTT -> CHANGE IT!

// get body from post
$postBody = file_get_contents('php://input');

// check if secret is valid
if (strpos($postBody, $secret) == false) {
    $errMsg = "Submitted body $postBody does not contain secret. -> Exit";
    logToFile($errMsg);
    print "$errMsg <br>";
    return;
}

try {

    if (!file_exists($statusFile)) {
        file_put_contents($statusFile, null);
    }

    if (!file_exists($statusFile) || !is_readable($statusFile)) {
        $errMsg = "Status File does not exist or is not readable!";
        logToFile($errMsg);
        print "$errMsg <br>";
        return;
    }
    if (!is_writable($statusFile)) {
        $errMsg = "Status File is not writable!";
        logToFile($errMsg);
        print "$errMsg <br>";
        return;
    }
    else {
        $fh = fopen($statusFile, 'w');
        fwrite($fh, $postBody);
        fclose($fh);
    }
}
catch (Exception $e) {
    logToFile($e->getMessage());
}

?>
