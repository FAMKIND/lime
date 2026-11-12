LIME-410 test fixtures, made once with openssl; the CA's private key was thrown away (nothing more can be signed by it).
 good.pem / good.pk8        a certificate for good.example signed by the debug-only test CA (src/debug/res/raw/lime_test_ca.pem)
 other.pem / other.pk8      a certificate for other.example signed by the same CA (a valid chain for the WRONG name)
 selfsigned.pem / .pk8      a self-signed certificate for good.example (not trusted by anything)
The CA is trusted only by debug builds (src/debug/res/xml/network_security_config_debug.xml debug-overrides); the release build does not have it.
