ui            = true
api_addr      = "https://127.0.0.1:8200"

listener "tcp" {
  address       = "0.0.0.0:8443"
  tls_cert_file = "/mnt/pki/server/server.crt"
  tls_key_file  = "/mnt/pki/server/server.key"
  tls_disable = "false"

}
