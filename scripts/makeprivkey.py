import base58check
import os
import hashlib
num = b'\xef' + bytearray([0]*32)
print(num.hex())
hash1 = hashlib.sha256(num).digest()
checksum = hashlib.sha256(hash1).digest()[:4]
print((num+checksum).hex())
encoded = base58check.b58encode(num+checksum)
print("btc-cli -rpcwallet=perf importprivkey ",ascii(encoded),"\"",ascii(encoded),"\" false")
