<?php 

//const PRIVATE_KEY = <<<EOD
//-----BEGIN RSA PRIVATE KEY-----
//MIICXwIBAAKBgQC+1xcYsEE+ab/Ame1/HHAgfBRhD67I9mBYCiOJqC3lJX5RKFvt
//OTcF5Sf5Bz3NL/2QWPLu40+yt4EvjZ3HOUAHrVgo2Fjo4vpaRoEaEtaccOziPH/A
//SScOfL+uppNGOa0glTCZLKVZI3Go8zoutr8VDw2dNT7rDM/4TvPjwMYd3QIDAQAB
//AoGBAL7C9n1hQfaHcnut4i8bWCHApgZXzNlpHekjSV7C1A2oKtopQ6qfdJbZ99kA
//GhDPFeGCaGPOqM32jJXiM4L/gTXxdaZMlthVgxQRqrnGkh4NqPQLAYo0qgb21TsY
//RE2BXdSET1E8WbGWjZ4508Jx6TNtTaSJJlgsSnqVibJHAEyBAkEA3i/+jif6KKVm
//Q0aS0TJIPCOjp2fmBfke27j/BdC2wJ5Arp1VO+sgKM8qJqaoOUCv+z08WGyIostF
//oOfRiGF9DQJBANvh3WQkbIjAgVrWoasHI54S7lz8kkeqKJ30LdIUK/1I9+rf3iy5
//YvSmrnH4VnTx4XfxemKfF+HQNnlqcf1sEBECQQCbidGTRl0S0yaRdfgVRjPXFcPc
//zxjxmYGGoyyzr3YfxSjWlAE03tY2ez+wqv4chjIrmKSD6gaEn/PwPhgqdsSJAkEA
//nRoW3ZsstNSeV7Hsls8mAqZSCrwnI+8O0DSLnILvHyxIfldvXZMjgdup3iJqW2oL
//B3DQWbCEFsJ2eW+1fDT+kQJBANUUbnJNJtrUMK013eEIWwgXLk7cnJ71CkhtnVUP
//6sK44uktZ2a6YSkpmcRPgniy6McUR8g58ZgMeXn5OUv91lU=
//-----END RSA PRIVATE KEY-----
//EOD;
    
const PRIVATE_KEY = <<<EOD
-----BEGIN RSA PRIVATE KEY-----
MIICXgIBAAKBgQDSs/E0vDEy9JDudWgnbcOyM68gog6r5xir+GVp7mcI4z5EKyKb
eQGySPLai5T9K11zcQlaENDTg0qMDn7/SSM2LysJw1Aw7Lc24BZff+FQY+/I/Fgy
iVosfftVdeg9BnKGLRagkANgD3oqMo9yGJo1/HBiXpbUG5t6MGAOFHwKoQIDAQAB
AoGBAK6DvY9pI/LJX9Uxxy+JGWJarn1/3FkDEos1NIIVpJ9W4DbD52kQQ5hwFT1w
CNnb9g3snMtNTDkz8CWqyAMXh6ISkhLufBQZek0StW9Qo4wDgONMO2phouI2AAMw
vRjXZQ3jxvQqrhCyqtS4RhxgoOso82ImMDK0mUzwE5yXZi5lAkEA+eu/1S+3Q6Px
icjCt/IS58j5oi/Oefhb6MGjmG5JJUyEDL4ph/FPBGbj3+NtFkDNYULn0pqYoaCK
XAD2iMnL7wJBANfT+8QXYTCwDIHCs44fv3fHt9sCqcBJFDuM7hoDHHNcTfflPTLR
LehckAb2rvCU+adKfztl4C0yHSQbCyMnQm8CQCvfoAib3M9KC5AFp3FFVN5N4M0B
GX0+BVyCCecrjTm4CgJ2q7HKwfVi3qQiN7dNXwCxDyNgsmTFWyS1opH24w8CQQCB
YzNG/mEkqBYHYKr2JDBL5a5iHLmZbfY0MSu46m6O9iJD3+kNYvvrljo+Ansj/Zuh
X/bgrBV14to3gALwQyP/AkEAwph98j0KboVsOTlWDt5ZOl0PiXER/2liZ9yZKkH5
Sz66E61PYY+WQE+7tszxdrS2kuSMjVHtx1R567G2Rg/mNg==
-----END RSA PRIVATE KEY-----
EOD;

$files = "";
$zipFile = "script.zip";
$finalFile = "v1";
for ($i = 1; $i < count($argv); $i ++) {
    if ($argv[$i] == '-o') {
        $finalFile = $argv[$i + 1];
        break;
    }
    $files .= $argv[$i] . " ";
}

if (!empty($files)) {

    //compress files
    echo system("zip $zipFile $files"); 

    //get and encrypt zip file's md5
    $zipFileMD5 = md5_file($zipFile);
    $private_key = openssl_pkey_get_private(PRIVATE_KEY);
    $ret = openssl_private_encrypt($zipFileMD5, $encrypted, $private_key);

    if (!$ret || empty($encrypted)) {
        unlink($zipFile);
        echo "fail to encrypt file md5";
    }

    $md5File = "key";
    file_put_contents($md5File, $encrypted);

    //pack script zip file and md5 file to final zip file
    echo system("zip $finalFile $zipFile $md5File"); 

    unlink($md5File);
    unlink($zipFile);
}
