set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
fi

# 2. Проверки по требованиям 4 и 5
# Требование 4: Файл index.html должен существовать
if [[ ! -f "${LOCAL_DIR}/index.html" ]]; then
    echo "ОШИБКА: Файл ${LOCAL_DIR}/index.html не найден. Доставка отменена." >&2
    exit 1
fi

# Требование 5: В репозитории не должно быть незафиксированных изменений
# Проверяем как рабочую директорию, так и индекс (staged changes)
if ! git diff-index --quiet HEAD -- || ! git diff-index --cached --quiet HEAD --; then
    echo "ОШИБКА: В репозитории есть незафиксированные изменения. Сделайте коммит." >&2
    exit 1
fi

# 3. Синхронизация каталога (Требование 3)
echo "Синхронизация ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}..."
# -e "ssh -o BatchMode=yes" гарантирует, что скрипт не будет запрашивать пароль (Требование 9)
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} -e "ssh -o BatchMode=yes" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности (Требование 1)
if [[ -n "${DRY_RUN}" ]]; then
    echo "Пробный запуск (dry-run) успешно завершен. Изменения не вносились."
    exit 0
fi

# 5. Проверка доступности SITE_URL (Требования 6 и 7)
echo "Проверка доступности ресурса ${SITE_URL}..."
# curl -f заставляет вернуть ошибку при HTTP-кодах 4xx или 5xx
# проверяем сертификат через --cacert (без отключения -k)
if curl -sf --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    SHORT_HASH=$(git rev-parse --short HEAD)
    echo "УСПЕХ: Ресурс доступен. Доставлен коммит: ${SHORT_HASH}"
    exit 0
else
    echo "ОШИБКА: Ресурс ${SITE_URL} недоступен после доставки." >&2
    exit 1
fi
