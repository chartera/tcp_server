srcDir        = "src"
binDir        = "bin"
bin           = @["tcp_server"]

# Package

version       = "0.1.1"
author        = "Nael Tasmim"
description   = "A tcp server"
license       = "BSD"

# Dependencies

requires "nim >= 0.17.2", "protocol", "crpl"

