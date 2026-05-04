#include "database/mysql/mysql_internal.hpp"
#include <format>
#include <stdexcept>
#include <string>
#include <vector>

namespace mysql_internal {

    bool shouldApplySslCA(const DatabaseConnectionInfo& info) {
        if (info.sslCACertPath.empty()) {
            return false;
        }

        switch (info.sslmode) {
        case SslMode::Require:
        case SslMode::VerifyCA:
        case SslMode::VerifyFull:
        case SslMode::VerifyIdentity:
            return true;
        default:
            return false;
        }
    }

    std::function<MYSQL*()> makeMysqlFactory(const DatabaseConnectionInfo& info) {
        return [info]() -> MYSQL* {
            MYSQL* conn = mysql_init(nullptr);
            if (!conn) {
                throw std::runtime_error("mysql_init failed");
            }

            constexpr unsigned int connectTimeoutSeconds = 5;
            mysql_options(conn, MYSQL_OPT_CONNECT_TIMEOUT, &connectTimeoutSeconds);

            if (shouldApplySslCA(info)) {
                mysql_options(conn, MYSQL_OPT_SSL_CA, info.sslCACertPath.c_str());
            }

            switch (info.sslmode) {
            case SslMode::Disable: {
                my_bool enforce = 0;
                mysql_options(conn, MYSQL_OPT_SSL_ENFORCE, &enforce);
                break;
            }
            case SslMode::Require: {
                my_bool enforce = 1;
                mysql_options(conn, MYSQL_OPT_SSL_ENFORCE, &enforce);
                break;
            }
            case SslMode::VerifyCA: {
                my_bool enforce = 1;
                mysql_options(conn, MYSQL_OPT_SSL_ENFORCE, &enforce);
                break;
            }
            case SslMode::VerifyFull:
            case SslMode::VerifyIdentity: {
                my_bool enforce = 1;
                my_bool verify = 1;
                mysql_options(conn, MYSQL_OPT_SSL_ENFORCE, &enforce);
                mysql_options(conn, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &verify);
                break;
            }
            default:
                break;
            }

            unsigned long flags = CLIENT_MULTI_STATEMENTS;
            if (!mysql_real_connect(conn, info.host.c_str(), info.username.c_str(),
                                    info.password.c_str(), info.database.c_str(), info.port,
                                    nullptr, flags)) {
                std::string err = mysql_error(conn);
                mysql_close(conn);
                throw std::runtime_error("MySQL connection failed: " + err);
            }
            mysql_set_character_set(conn, "utf8mb4");
            return conn;
        };
    }

    StatementResult extractMysqlResult(MYSQL* conn, int rowLimit) {
        StatementResult result;

        MYSQL_RES* rawRes = mysql_store_result(conn);
        if (rawRes) {
            MysqlResPtr res(rawRes);
            unsigned int nFields = mysql_num_fields(res.get());
            MYSQL_FIELD* fields = mysql_fetch_fields(res.get());

            std::vector<bool> isBoolCol(nFields, false);
            for (unsigned int i = 0; i < nFields; i++) {
                result.columnNames.emplace_back(fields[i].name);
                isBoolCol[i] = (fields[i].type == MYSQL_TYPE_TINY && fields[i].length == 1);
            }

            int rowCount = 0;
            MYSQL_ROW row;
            while ((row = mysql_fetch_row(res.get())) != nullptr && rowCount < rowLimit) {
                unsigned long* lengths = mysql_fetch_lengths(res.get());
                std::vector<std::string> rowData;
                rowData.reserve(nFields);
                for (unsigned int i = 0; i < nFields; i++) {
                    if (row[i] == nullptr) {
                        rowData.emplace_back("NULL");
                    } else if (isBoolCol[i]) {
                        rowData.emplace_back(row[i][0] == '1' ? BOOL_TRUE_SENTINEL
                                                              : BOOL_FALSE_SENTINEL);
                    } else {
                        rowData.emplace_back(row[i], lengths[i]);
                    }
                }
                result.tableData.push_back(std::move(rowData));
                rowCount++;
            }

            result.message = std::format("Returned {} row{}", result.tableData.size(),
                                         result.tableData.size() == 1 ? "" : "s");
            my_ulonglong totalRows = mysql_num_rows(res.get());
            if (static_cast<int>(totalRows) >= rowLimit) {
                result.message += std::format(" (limited to {})", rowLimit);
            }
        } else {
            if (mysql_field_count(conn) == 0) {
                my_ulonglong affected = mysql_affected_rows(conn);
                if (affected != (my_ulonglong)-1) {
                    result.message = std::format("{} row(s) affected", affected);
                } else {
                    result.message = "Query executed successfully";
                }
            } else {
                result.success = false;
                result.errorMessage = mysql_error(conn);
            }
        }

        return result;
    }

} // namespace mysql_internal
