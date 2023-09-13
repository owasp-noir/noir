import hashlib 

def get_hash(data, salt):
    m = len(salt)//2
    sdata = salt[:m] + data + salt[m:]
    return hashlib.sha256(sdata.encode('utf-8')).hexdigest()
