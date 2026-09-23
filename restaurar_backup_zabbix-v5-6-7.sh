#!/usr/bin/env bash
# ==============================================================================
# Script de Restauração Automatizada - Zabbix 7.0 LTS
# Compatibilidade: Debian 12/13 e Ubuntu Server (MariaDB / MySQL)
# ==============================================================================

set -e

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_splash() {
    clear
    echo -e "\e[31m"
    echo "███████╗ █████╗ ██████╗ ██████╗ ██╗██╗  ██╗"
    echo "╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██║╚██╗██╔╝"
    echo "  ███╔╝ ███████║██████╔╝██████╔╝██║ ╚███╔╝ "
    echo " ███╔╝  ██╔══██║██╔══██╗██╔══██╗██║ ██╔██╗ "
    echo "███████╗██║  ██║██████╔╝██████╔╝██║██╔╝ ██╗"
    echo "╚══════╝╚═╝  ╚═╝╚═════╝╚═════╝ ╚═╝╚═╝  ╚═╝"
    echo -e "\e[0m"
    echo "========================================================"
    echo "            RESTAURAÇÃO ZABBIX 7 LTS"
    echo "========================================================"
    echo ""
    sleep 1
}

show_splash

BACKUP_DIR="/backup_zabbix"

# 1. Validação de privilégios
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}❌ Este script deve ser executado como root.${NC}" >&2
    exit 1
fi

# 2. Seleção interativa do snapshot de backup
selecionar_backup() {
    echo -e "\n📂 ${BLUE}Snapshots de backup disponíveis em $BACKUP_DIR:${NC}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ Diretório $BACKUP_DIR não existe.${NC}"
        exit 1
    fi

    # Mapeia diretórios iniciados por bkp_
    mapfile -t backups < <(ls -1td "$BACKUP_DIR"/bkp_* 2>/dev/null | xargs -n1 basename 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}❌ Nenhum diretório de backup (bkp_*) encontrado em $BACKUP_DIR.${NC}"
        exit 1
    fi

    for i in "${!backups[@]}"; do
        local dir_size
        dir_size=$(du -sh "$BACKUP_DIR/${backups[$i]}" | cut -f1)
        echo -e "  ${YELLOW}$((i+1)).${NC} ${backups[$i]} (${dir_size})"
    done

    echo ""
    while true; do
        read -rp "👉 Selecione o backup para restaurar [1-${#backups[@]}]: " backup_num
        if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le "${#backups[@]}" ]; then
            selected_backup="${backups[$((backup_num-1))]}"
            BACKUP_PATH="$BACKUP_DIR/$selected_backup"
            break
        else
            echo -e "${RED}Opção inválida. Digite um número da lista.${NC}"
        fi
    done

    echo -e "\n🔍 ${BLUE}Artefatos identificados no snapshot selecionado:${NC}"
    ls -lh "$BACKUP_PATH"
}

# 3. Execução da restauração
restaurar_zabbix() {
    echo -e "\n🔵 ${BLUE}Iniciando procedimento de Restauração...${NC}"

    local zabbix_db_file
    zabbix_db_file=$(find "$BACKUP_PATH" -name "zabbix_db_*.sql.gz" | head -1)

    if [ ! -f "$zabbix_db_file" ]; then
        echo -e "${RED}❌ Erro: Arquivo relacional (zabbix_db_*.sql.gz) não encontrado em $BACKUP_PATH.${NC}"
        exit 1
    fi

    # Credenciais do Banco
    read -rp "👉 Usuário do MariaDB/MySQL [Padrão: zabbix]: " mysql_user
    mysql_user=${mysql_user:-zabbix}

    read -rsp "🔒 Senha do MariaDB/MySQL [Padrão: zabbix]: " mysql_pass
    echo ""
    mysql_pass=${mysql_pass:-zabbix}

    # Interrompe daemons para evitar gravações concorrentes
    echo -e "\n🛑 ${YELLOW}[1/5] Parando serviços para garantir integridade referencial...${NC}"
    systemctl stop zabbix-server zabbix-agent apache2 2>/dev/null || true

    # Libera criação de funções e triggers sem restrição estrita de binlog
    echo -e "🔓 ${YELLOW}[2/5] Ajustando diretivas de compatibilidade de funções (Erro 1419)...${NC}"
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;" 2>/dev/null || true

    # Recriação estrita da base com UTF8MB4_BIN (Exigência Zabbix 7.0 LTS)
    echo -e "🧹 ${YELLOW}[3/5] Recriando base de dados com collation oficial (utf8mb4_bin)...${NC}"
    if ! MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" -e "DROP DATABASE IF EXISTS zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"; then
        echo -e "${RED}❌ Falha ao recriar banco de dados. Verifique usuário e senha informados.${NC}"
        mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true
        exit 1
    fi

    # Injeção direta sem alteração destrutiva de caracteres
    echo -e "🔄 ${YELLOW}[4/5] Injetando dump relacional (isto pode levar alguns minutos)...${NC}"
    set -o pipefail
    local err_log
    err_log=$(mktemp)

    if ! zcat "$zabbix_db_file" | MYSQL_PWD="$mysql_pass" mysql -u "$mysql_user" zabbix 2>"$err_log"; then
        echo -e "${RED}❌ Falha na injeção dos dados relacionais:${NC}"
        cat "$err_log"
        rm -f "$err_log"
        mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true
        exit 1
    fi
    set +o pipefail
    rm -f "$err_log"
    echo -e "  ${GREEN}✔ Banco de dados importado com sucesso.${NC}"

    # Retorna segurança de binlogs
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;" 2>/dev/null || true

    # Restauração de arquivos de sistema e templates
    echo -e "📦 ${YELLOW}[5/5] Restaurando arquivos físicos e configurações...${NC}"
    local zabbix_files
    zabbix_files=$(find "$BACKUP_PATH" -name "zabbix_dirs_*.tar.gz" | head -1)

    if [ -f "$zabbix_files" ]; then
        tar -xzf "$zabbix_files" -C /
        echo -e "  ${GREEN}✔ Configurações e diretórios restaurados na raiz.${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Aviso: Arquivo de diretórios não encontrado. Apenas a base foi restaurada.${NC}"
    fi

    # Reinicialização dos serviços
    echo -e "\n🚀 ${BLUE}Reiniciando ecossistema de monitoramento...${NC}"
    systemctl restart mariadb 2>/dev/null || true
    systemctl restart zabbix-server zabbix-agent apache2
    
    # Reinicia PHP-FPM dinamicamente caso esteja em execução
    PHP_SVC=$(systemctl list-units --type=service --state=running | grep -oE "php[0-9.]+-fpm" | head -1 || true)
    [ -n "$PHP_SVC" ] && systemctl restart "$PHP_SVC"

    # Validação ativa de disponibilidade
    sleep 2
    if systemctl is-active --quiet zabbix-server; then
        echo -e "${GREEN}========================================================"
        echo -e "   ✅ RESTAURAÇÃO CONCLUÍDA: ZABBIX TOTALMENTE OPERACIONAL!"
        echo -e "========================================================${NC}"
    else
        echo -e "${RED}⚠️  Alerta: O daemon do Zabbix Server não subiu automaticamente. Verifique '/var/log/zabbix/zabbix_server.log'.${NC}"
    fi
}

selecionar_backup
restaurar_zabbix
