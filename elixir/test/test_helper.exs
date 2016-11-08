# Need to set up some valid secrets for the doctests to work
File.mkdir_p! "./test/doc_secrets"
File.write!   "./test/doc_secrets/MYSQL_USER", "admin"
File.write!   "./test/doc_secrets/MYSQL_PASS", "password"
File.touch!   "./test/doc_secrets/.done"

ExUnit.start()
