# ♻️ Zabbix Auto Restore

<p align="center">

![Bash](https://img.shields.io/badge/Bash-Script-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Compatible-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Debian](https://img.shields.io/badge/Debian-Supported-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-Supported-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Zabbix](https://img.shields.io/badge/Zabbix-7.0_LTS-D40000?style=for-the-badge)
![MySQL](https://img.shields.io/badge/MySQL-Restore-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-Supported-003545?style=for-the-badge&logo=mariadb&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

</p>

Script desenvolvido para realizar a **recuperação automatizada de desastres (Disaster Recovery)** em ambientes Zabbix Server (com suporte nativo ao **Zabbix 7.0 LTS** e compatível com versões 5.0 e 6.0 LTS em ambientes homogêneos). 

A rotina assegura a integridade de dados ao restaurar a base relacional MySQL/MariaDB sob a collation oficial `utf8mb4_bin` e extrair os arquivos de configuração do sistema, reduzindo o RTO (*Recovery Time Objective*) operacional.

---

# 📦 Sobre o Projeto

Este utilitário faz parte de uma suíte de automação para o ecossistema Zabbix, cobrindo o ciclo de vida completo de provisionamento, rotinas de backup e restauração automatizada.

O script foi concebido com foco em confiabilidade: interrompe serviços para prevenir gravações concorrentes, trata privilégios de binlogs (`log_bin_trust_function_creators`) para evitar o Erro 1419 e valida a injeção contínua de dados em tempo real (*fail-fast*).

---

# ✨ Funcionalidades

- ♻️ **Restauração Completa de DR:** Recupera base de dados relacional e arquivos de configuração do sistema operacional.
- 📂 **Menu Interativo e Dinâmico:** Listagem automática dos snapshots disponíveis com detecção de tamanho e ordenação temporal via `mapfile`.
- 🛢️ **Conformidade de Banco de Dados:** Criação padronizada da base sob codificação `utf8mb4` e collation binária estrita (`utf8mb4_bin`), atendendo aos requisitos oficiais do Zabbix 7.0 LTS.
- 🛡️ **Injeção Segura (*Stream-Safe*):** Importação contínua via `zcat` com tratamento de pipeline (`pipefail`), eliminando riscos de corrupção em procedimentos armazenados e triggers.
- 🛑 **Orquestração Graciosa de Serviços:** Interrupção e retomada automatizada de `zabbix-server`, `zabbix-agent`, `apache2` e pools ativos de `php-fpm`.
- 🔒 **Gestão Dinâmica de Privilégios:** Controle automático do parâmetro `log_bin_trust_function_creators` no MySQL/MariaDB durante o processo.
- 🔍 **Validação Operacional Pós-Execução:** Verificação ativa de disponibilidade dos daemons via `systemctl is-active`.

---

# 📁 Estrutura esperada

Os backups devem estar armazenados em:

```text
/backup_zabbix
```

Exemplo:

```text
/backup_zabbix

├── bkp_2026-07-30
│   ├── zabbix_db_20260730.sql.gz
│   └── zabbix_dirs_20260730.tar.gz
│
├── bkp_2026-07-29
│   ├── zabbix_db_20260729.sql.gz
│   └── zabbix_dirs_20260729.tar.gz
│
└── bkp_2026-07-28
    ├── zabbix_db_20260728.sql.gz
    └── zabbix_dirs_20260728.tar.gz
```

---

# 📦 Arquivos esperados

Cada backup deve conter:

| Arquivo | Descrição |
|----------|-----------|
| `zabbix_db_*.sql.gz` | Dump compactado do banco de dados |
| `zabbix_dirs_*.tar.gz` | Backup dos arquivos do Zabbix |

Caso apenas o banco esteja presente, o script continuará normalmente e restaurará somente os dados.

---

# ⚙️ Como funciona

O processo de restauração é dividido em várias etapas para garantir a consistência do ambiente.

---

## 1️⃣ Seleção do backup

O script lista automaticamente todos os backups encontrados.

Exemplo:

```text
1. bkp_2026-07-30

2. bkp_2026-07-29

3. bkp_2026-07-28
```

Após selecionar o backup, seus arquivos são exibidos para conferência.

---

## 2️⃣ Coleta das credenciais

São solicitadas as credenciais do banco de dados:

- usuário MySQL;
- senha.

Essas informações são utilizadas para recriar o banco do Zabbix.

---

## 3️⃣ Parada dos serviços

São interrompidos automaticamente:

- Zabbix Server
- Zabbix Agent
- Apache

Isso evita gravações concorrentes durante a restauração.

---

## 4️⃣ Preparação do banco

O script:

- habilita temporariamente `log_bin_trust_function_creators`;
- remove o banco existente;
- cria um banco limpo;
- prepara o ambiente para importação.

---

## 5️⃣ Importação do banco

O dump SQL compactado é descompactado e injetado diretamente na base de dados (`zcat | mysql`) em fluxo contínuo (*stream*).

Para mitigar riscos de corrupção, o fluxo dispensa substituições manuais de texto via filtros destrutivos, preservando a integridade referencial de stored procedures, triggers e metadados binários. A diretiva `pipefail` do shell é ativada para que qualquer falha na injeção interrompa imediatamente a rotina e registre o erro em arquivo temporário isolado.

---

## 6️⃣ Restauração dos arquivos

Caso exista um arquivo:

```text
zabbix_dirs_*.tar.gz
```

ele será extraído automaticamente, restaurando:

- configurações;
- scripts;
- arquivos adicionais do ambiente.

Caso esse arquivo não exista, somente o banco de dados será restaurado.

---

## 7️⃣ Inicialização

Ao finalizar:

- o parâmetro de segurança do MySQL é restaurado;
- os serviços do Zabbix são iniciados novamente.

---

# 🔄 Fluxo da restauração

```text
Selecionar Backup
        │
        ▼
Solicitar Credenciais
        │
        ▼
Parar Serviços
        │
        ▼
Recriar Banco
        │
        ▼
Importar Banco
        │
        ▼
Restaurar Arquivos
        │
        ▼
Iniciar Serviços
        │
        ▼
Restauração Finalizada
```

---

# ▶️ Execução

Conceda permissão ao script:

```bash
chmod +x restore_zabbix7.sh
```

Execute como root:

```bash
sudo ./restore_zabbix7.sh
```

---

# 📋 Etapas exibidas

Durante a restauração são exibidas mensagens semelhantes a:

```text
Selecionando backup...

Parando serviços...

Recriando banco...

Importando banco...

Restaurando arquivos...

Reiniciando serviços...

Restauração concluída!
```

---

# 🔒 Segurança e Práticas Recomendadas

* **Integridade de Dados:** O script descarta a base atual (`DROP DATABASE IF EXISTS zabbix`) antes da injeção para assegurar que não haja conflito de chaves primárias ou tabelas órfãs.
* **Diagnósticos Isolados:** Erros de sintaxe ou de permissão do banco são gravados em arquivos temporários via `mktemp` com permissão restrita, evitando a exposição de credenciais no terminal.
* **Compatibilidade Homogênea:** Para restaurações que envolvam o arquivo `zabbix_dirs_*.tar.gz`, certifique-se de que a máquina de destino possui a mesma versão do Zabbix Server e PHP para evitar inconsistências nos módulos web.

---

# 📌 Pré-requisitos

- Debian ou Ubuntu
- MySQL ou MariaDB instalado
- Permissão de root
- Backup previamente gerado
- Diretório `/backup_zabbix`

---

# 📊 Exemplo de saída

```text
Backup selecionado:

bkp_2026-07-30

Banco restaurado com sucesso.

Arquivos restaurados.

Serviços iniciados.

Restauração concluída!
```

---

# ✅ Benefícios

- Processo totalmente automatizado
- Compatível com MySQL e MariaDB
- Conversão automática entre versões
- Restauração rápida
- Interface simples e intuitiva
- Ideal para Disaster Recovery
- Recuperação completa do ambiente
- Compatível com os backups gerados pelo script **Zabbix Backup**

---

# 🛠️ Tecnologias e Utilitários

* **Bash** (Orquestração de pipeline, `pipefail` e arrays via `mapfile`)
* **MariaDB / MySQL Client** (Engine relacional e execução DDL/DML)
* **gzip / zcat** (Descompressão em fluxo contínuo)
* **tar** (Descompactação de diretórios estruturais)
* **systemd** (Gerenciamento e inspeção de serviços)

---

# 📄 Licença

Este projeto está licenciado sob a licença **MIT**.

Você pode utilizar, modificar e distribuir este projeto livremente, desde que mantenha os créditos e o texto da licença.

---

# 👨‍💻 Autor

Desenvolvido para automatizar a restauração de ambientes **Zabbix 5.0, 6.0 e 7.0 LTS**, reduzindo o tempo de recuperação, padronizando procedimentos de Disaster Recovery e simplificando a administração de servidores Linux.
```
