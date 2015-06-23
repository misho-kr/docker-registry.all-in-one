#!/bin/sh
# --------------------------------------------------------------------------

PRIVATE_LEY_LEN=2048			# bits
SSL_CERTIFICATE_VALID=3650		# days

CERT_DOMAIN="docker-registry.fqdn"
CERT_EMAIL="docker-registry-admin@fqdn"

# --------------------------------------------------------------------------

answers() {
    echo US
    echo CA
    echo San Jose
    echo PayPal
    echo PayPal Cloud Organization
    echo "${CERT_DOMAIN}"
    echo "${CERT_EMAIL}"
}

# --------------------------------------------------------------------------

set -e
umask 077

while getopts "d:e:" opt; do
    case "${opt}" in
        d )	CERT_DOMAIN="${OPTARG}"	;;
        e )	CERT_EMAIL="${OPTARG}"	;;
        * )
            echo "usage: $0 [ -d certificate domain ] [ -e certificate email ] prefix"
            exit 1
            ;;
    esac
done

shift $((OPTIND - 1))

if [ $# -eq 0 ] ; then
    echo $"Usage: `basename $0` prefix"
    exit 1
fi

SSL_KEY="${1}.key"
SSL_CERTIFICATE="${1}.crt"

export RANDFILE=/tmp/openssl_seed_file

answers | \
    /usr/bin/openssl req -newkey rsa:${PRIVATE_LEY_LEN} \
    	-keyout ${SSL_KEY} -nodes -x509 -days "${SSL_CERTIFICATE_VALID}" \
    	-out ${SSL_CERTIFICATE} \
    	2> /dev/null

echo ""
echo "Private key and (self-signed) SSL certificate created:"
echo "------------------------------------------------------"
echo ""

openssl rsa -in ${1}.key -text -noout | head -1
openssl x509 -in ${1}.crt -text -noout | head -13

echo ""

# --------------------------------------------------------------------------
# eof
