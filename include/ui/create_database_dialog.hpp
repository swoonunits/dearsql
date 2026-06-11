#pragma once

#include "database/async_helper.hpp"
#include <memory>
#include <string>
#include <utility>
#include <vector>

class Application;
class DatabaseInterface;

// imgui-based create-database dialog (postgres/redshift and mysql/mariadb).
// render() must be called once per frame from the main render loop.
class CreateDatabaseDialog {
public:
    static CreateDatabaseDialog& instance();

    CreateDatabaseDialog(const CreateDatabaseDialog&) = delete;
    CreateDatabaseDialog& operator=(const CreateDatabaseDialog&) = delete;

    void show(Application* app, std::shared_ptr<DatabaseInterface> db);
    void render();

    [[nodiscard]] bool isOpen() const {
        return open_;
    }

private:
    CreateDatabaseDialog() = default;
    ~CreateDatabaseDialog() = default;

    struct PgOptions {
        std::vector<std::string> owners;
        std::vector<std::string> templates;
        std::vector<std::string> tablespaces;
    };

    [[nodiscard]] bool isPostgres() const;

    void startPostgresOptionsLoad();
    void pollPostgresOptions();
    void rebuildCollations();
    void setStatus(const std::string& text, bool isError);
    void startCreate();
    void pollCreate();
    void finishClose();

    Application* app_ = nullptr;
    std::shared_ptr<DatabaseInterface> db_;
    bool open_ = false;
    bool pendingOpen_ = false;
    bool closeRequested_ = false;

    char nameBuf_[256] = {};
    char commentBuf_[512] = {};

    // postgres
    std::vector<std::string> owners_;
    int ownerIdx_ = 0;
    std::vector<std::string> templates_;
    int templateIdx_ = 0;
    int encodingIdx_ = 0;
    std::vector<std::string> tablespaces_;
    int tablespaceIdx_ = 0;

    // mysql
    int charsetIdx_ = 0;
    std::vector<std::string> collations_;
    int collationIdx_ = 0;

    std::string statusText_;
    bool statusIsError_ = false;

    AsyncOperation<std::pair<bool, std::string>> createOp_;
    AsyncOperation<PgOptions> optionsOp_;
    bool loadingOptions_ = false;
};
