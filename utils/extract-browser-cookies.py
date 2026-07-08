#!/usr/bin/env python3
"""Extract cookies from Chromium-based browsers using the GNOME keyring.

Usage: extract-browser-cookies.py BROWSER [OUTPUT_FILE]

BROWSER: chromium, chrome, brave, vivaldi, edge, opera
"""

import os, sys, sqlite3, shutil, tempfile
from pathlib import Path

BROWSER_DB_PATHS = {
    "chromium": "chromium/Default/Cookies",
    "chrome":   "google-chrome/Default/Cookies",
    "brave":    "BraveSoftware/Brave-Browser/Default/Cookies",
    "vivaldi":  "vivaldi/Default/Cookies",
    "edge":     "microsoft-edge/Default/Cookies",
    "opera":    "opera/Cookies",
}

BROWSER_KEYRING_LABEL = {
    "chromium": "Chromium Safe Storage",
    "chrome":   "Chrome Safe Storage",
    "brave":    "Brave Safe Storage",
    "vivaldi":  "Chrome Safe Storage",
    "edge":     "Chromium Safe Storage",
    "opera":    "Chromium Safe Storage",
}


def get_key(browser):
    try:
        import secretstorage
    except ImportError:
        return None
    label = BROWSER_KEYRING_LABEL.get(browser, "Chromium Safe Storage")
    bus = secretstorage.dbus_init()
    col = secretstorage.get_default_collection(bus)
    if col.is_locked():
        col.unlock()
    for item in col.get_all_items():
        if item.get_label() == label:
            return item.get_secret()
    return None


def decrypt_cookie(key, encrypted_value, hash_prefix=True):
    from Cryptodome.Cipher import AES
    from Cryptodome.Util.Padding import unpad
    import hashlib
    if not encrypted_value or len(encrypted_value) < 4:
        return ""
    version = encrypted_value[:3]
    ciphertext = encrypted_value[3:]
    if version == b"v11":
        derived = hashlib.pbkdf2_hmac("sha1", key, b"saltysalt", 1, dklen=16)
    elif version == b"v10":
        derived = hashlib.pbkdf2_hmac("sha1", b"peanuts", b"saltysalt", 1, dklen=16)
    else:
        try:
            return encrypted_value.decode("utf-8")
        except Exception:
            return ""
    iv = b" " * 16
    try:
        cipher = AES.new(derived, AES.MODE_CBC, iv)
        decrypted = unpad(cipher.decrypt(ciphertext), AES.block_size)
        if hash_prefix:
            decrypted = decrypted[32:]
        return decrypted.decode("utf-8")
    except Exception:
        return ""


def extract_cookies(browser, output_file=None):
    db_rel = BROWSER_DB_PATHS.get(browser)
    if db_rel is None:
        return False
    db_path = Path.home() / ".config" / db_rel
    if not db_path.exists():
        return False
    key = get_key(browser)
    if key is None:
        return False
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        tmp_path = tmp.name
    shutil.copy2(db_path, tmp_path)
    try:
        conn = sqlite3.connect(tmp_path)
        cur = conn.cursor()
        try:
            meta_ver = int(cur.execute("SELECT value FROM meta WHERE key = 'version'").fetchone()[0])
        except Exception:
            meta_ver = 0
        cur.execute("SELECT host_key, name, path, is_secure, expires_utc, is_httponly, encrypted_value FROM cookies")
        rows = cur.fetchall()
        conn.close()
    finally:
        os.unlink(tmp_path)
    out = open(output_file, "w") if output_file else sys.stdout
    count = 0
    try:
        out.write("# Netscape HTTP Cookie File\n")
        for host, name, path, secure, expires, httponly, enc_val in rows:
            value = decrypt_cookie(key, enc_val, hash_prefix=(meta_ver >= 24))
            if not value:
                continue
            domain_flag = "TRUE" if host.startswith(".") else "FALSE"
            secure_str = "TRUE" if secure else "FALSE"
            if expires:
                unix_ts = int((expires / 1_000_000) - 11644473600)
                if unix_ts < 0:
                    unix_ts = 0
            else:
                unix_ts = 0
            out.write(f"{host}\t{domain_flag}\t{path}\t{secure_str}\t{unix_ts}\t{name}\t{value}\n")
            count += 1
    finally:
        if output_file:
            out.close()
    print(f"Extracted {count} cookies from {browser}", file=sys.stderr)
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: extract-browser-cookies.py BROWSER [OUTPUT_FILE]", file=sys.stderr)
        sys.exit(1)
    browser = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else None
    sys.exit(0 if extract_cookies(browser, output) else 1)


if __name__ == "__main__":
    main()
