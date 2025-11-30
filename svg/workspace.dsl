workspace "SuperSurance Architecture" "Архитектура системы расчета страховых премий (Результаты Семинара 1 + Уточнения) и Системы Уведомлений (Семинар 2)" {

    model {
        # ---------------------------------------------------------------------
        # 1. Actors (Пользователи)
        # ---------------------------------------------------------------------
        customer = person "Клиент" "Физическое лицо, запрашивающее расчет КАСКО." "Person"
        underwriter = person "Андеррайтер" "Сотрудник, вручную оценивающий сложные риски." "Person,Employee"
        admin = person "Администратор" "Настройка тарифов, продуктов и управление доступом." "Person,Employee"
        partner_agent = person "Агент Партнера" "Представитель партнерской сети продаж." "Person,External"

        # ---------------------------------------------------------------------
        # 2. External Systems (Внешнее окружение)
        # ---------------------------------------------------------------------
        group "Внешние провайдеры данных" {
            ext_repairs = softwareSystem "Сервис Истории Ремонтов" "Предоставляет историю ремонтов ТС." "External System"
            ext_market_value = softwareSystem "Сервис Оценки Стоимости" "Оценка рыночной стоимости ТС." "External System"
            ext_fines = softwareSystem "Сервис Штрафов" "История штрафов водителя." "External System"
            ext_antifraud = softwareSystem "Антифрод Система" "Проверка на мошенничество." "External System"
        }
        
        group "Провайдеры Коммуникаций" {
            ext_sms = softwareSystem "SMS Gateway" "Агрегатор SMS (Twilio/SMPP)." "External System"
            ext_email = softwareSystem "Email Provider" "Сервис рассылок (SendGrid/SMTP)." "External System"
            ext_telegram = softwareSystem "Telegram API" "Мессенджер." "External System"
            ext_push = softwareSystem "Push Notification Service" "FCM / APNS." "External System"
        }

        payment_gateway = softwareSystem "Платежный Шлюз" "Обработка платежей по картам." "External System"

        # ---------------------------------------------------------------------
        # 3. Target System (SuperSurance)
        # ---------------------------------------------------------------------
        insuranceSystem = softwareSystem "Система Расчета Премий (SuperSurance)" "Рассчитывает стоимость КАСКО, управляет предложениями и полисами." {
            
            # --- Frontend Layer ---
            spa = container "Web Application" "Личный кабинет клиента и сотрудника." "React / JavaScript" "Web Browser"
            mobile_app = container "Mobile App" "Мобильное приложение для клиентов." "Flutter / Dart" "Mobile App"
            api_gateway = container "API Gateway" "Единая точка входа, маршрутизация, rate limiting." "Nginx / Spring Cloud Gateway" "Gateway"

            # --- Platform Services ---
            auth_service = container "Auth Service (RBAC)" "Аутентификация и авторизация пользователей." "Keycloak / OIDC" "Service"
            doc_service = container "Documents Service" "Генерация печатных форм (PDF)." "Java / Spring Boot" "Service"
            ref_data_service = container "Reference Data Service" "Справочники (регионы, марки авто)." "Java / Spring Boot" "Service"
            
            # --- Domain Services (Core Business) ---
            
            # Calculation Engine - Выделенная логика расчетов
            calc_service = container "Calculation Engine" "Выполняет математический расчет премии." "Java / Spring Boot / Drools" "Service" {
                description "Stateless сервис. Применяет тарифные правила к контексту клиента."
            }

            tariff_service = container "Product & Tariffs Service" "Хранение версий продуктов и правил тарификации." "Java / Spring Boot" "Service"
            crm_service = container "CRM Service" "Управление данными клиентов." "Java / Spring Boot" "Service"
            partner_service = container "Partner Network Service" "Управление партнерами и агентскими продажами." "Java / Spring Boot" "Service"
            portfolio_service = container "Portfolio Monitoring" "Мониторинг действующего портфеля договоров." "Java / Spring Boot" "Service"
            tasks_service = container "Tasks Service" "Управление задачами ручного разбора (для андеррайтеров)." "Java / Spring Boot" "Service"

            # Proposals Service (Detailed Components)
            proposals_service = container "Proposals Service" "Оркестрация расчета премий, сохранение заявок." "Java / Spring Boot" "Service" {
                
                # Components
                prop_ctrl = component "Proposal Controller" "Обрабатывает входящие HTTP запросы." "Spring MVC"
                prop_orch = component "Proposal Orchestrator" "Координирует процесс обогащения и расчета." "Spring Service"
                workflow = component "Workflow Engine" "Управляет статусами (Draft -> Calculated -> Issued)." "State Machine"
                prop_repo = component "Proposal Repository" "Сохраняет заявки." "JPA Repository"
                
                # Clients (Gateways)
                client_crm = component "CRM Client" "Фасад для вызова CRM." "Feign Client"
                client_calc = component "Calculation Client" "Фасад для вызова Calculation Engine." "gRPC Client"
                client_acl = component "ACL Client" "Фасад для вызова внешних данных." "Feign Client"
                
                kafka_prod = component "Event Publisher" "Публикует события в брокер." "Kafka Producer"

                # Component Relationships
                api_gateway -> prop_ctrl "Запрос расчета"
                prop_ctrl -> prop_orch "Запуск процесса"
                prop_orch -> workflow "Проверка перехода"
                prop_orch -> prop_repo "Persist"
                
                prop_orch -> client_crm "1. Получить данные клиента"
                prop_orch -> client_acl "2. Обогатить данными авто"
                prop_orch -> client_calc "3. Рассчитать стоимость"
                prop_orch -> kafka_prod "4. Опубликовать событие"
            }
            
            # Notification Service (Detailed Components based on Seminar 2)
            notification_service = container "Notification Service" "Центр уведомлений (SMS, Email, Push)." "Java / Spring Boot" "Service" {
                description "Единая точка входа для отправки уведомлений. Поддерживает шаблонизацию и многоканальность."

                # Входные точки
                notif_api = component "Notification API" "REST API для прямой отправки и управления шаблонами." "Spring MVC"
                notif_consumer = component "Notification Consumer" "Слушает события (ProposalCreated, etc)." "Kafka Listener"

                # Логика
                notif_orch = component "Delivery Orchestrator" "Координатор. Определяет получателя, выбирает шаблон и канал." "Spring Service"
                recipient_resolver = component "Recipient Resolver" "Определяет контактные данные по ID пользователя." "Spring Component"
                template_engine = component "Template Engine" "Рендерит сообщение на основе шаблона и данных." "Velocity / Freemarker"
                retry_manager = component "Retry & Failover Manager" "Управляет повторными отправками при сбоях." "Spring Retry"

                # Хранение
                notif_repo = component "Notification Repository" "Сохраняет историю, статус и шаблоны." "Spring Data JPA"

                # Адаптеры каналов
                adapter_email = component "Email Adapter" "Адаптер для Email провайдера." "Java Component"
                adapter_sms = component "SMS Adapter" "Адаптер для SMS шлюза." "Java Component"
                adapter_tg = component "Telegram Adapter" "Адаптер для Telegram Bot API." "Java Component"
                adapter_push = component "Push Adapter" "Адаптер для Push уведомлений." "Java Component"

                # Связи
                api_gateway -> notif_api "Управление шаблонами / Прямая отправка"
                
                notif_api -> notif_orch "Запрос на отправку"
                notif_consumer -> notif_orch "Событие на отправку"

                notif_orch -> recipient_resolver "1. Найти контакты"
                notif_orch -> template_engine "2. Сформировать тело"
                notif_orch -> notif_repo "3. Сохранить историю (Pending)"
                notif_orch -> retry_manager "4. Передать в доставку"

                retry_manager -> adapter_email "Отправка Email"
                retry_manager -> adapter_sms "Отправка SMS"
                retry_manager -> adapter_tg "Отправка TG"
                retry_manager -> adapter_push "Отправка Push"
                retry_manager -> notif_repo "Обновить статус (Sent/Error)"

                # Связи внутри Resolvers
                recipient_resolver -> client_crm "Запрос контактов (через API CRM)"
            }
            
            # --- Integration & Views ---
            service_facade = container "Service Facade (CQRS)" "Агрегация данных для UI (Read Model)." "Java / Spring Boot" "Service"
            acl_service = container "Anti-Corruption Layer (ACL)" "Адаптер к внешним сервисам данных." "Java / Spring Boot" "Service"

            # --- Data Stores ---
            db_proposals = container "Proposals DB" "Заявки." "PostgreSQL" "Database"
            db_crm = container "CRM DB" "Клиенты." "PostgreSQL" "Database"
            db_tariffs = container "Tariffs DB" "Тарифы." "PostgreSQL" "Database"
            db_notifications = container "Notifications DB" "Шаблоны, логи отправки, статусы." "PostgreSQL" "Database"
            db_read_model = container "Read Model DB" "Витрины данных." "PostgreSQL / Elastic" "Database"
            file_storage = container "File Storage (S3)" "Документы." "MinIO" "Storage"
            
            message_broker = container "Message Broker" "Kafka" "Kafka" "Broker"
        }

        # ---------------------------------------------------------------------
        # 4. Relationships (Global)
        # ---------------------------------------------------------------------
        
        # User -> System
        customer -> spa "Использует"
        underwriter -> spa "Использует"
        admin -> spa "Использует"
        partner_agent -> spa "Использует"

        # SPA/Mobile -> Gateway
        spa -> api_gateway "HTTPS/JSON"
        mobile_app -> api_gateway "HTTPS/JSON"
        api_gateway -> auth_service "Auth check"

        # Gateway -> Containers
        api_gateway -> service_facade "Чтение списков (Query)"
        api_gateway -> tasks_service "Управление задачами"

        # Inter-service (Synchronous / RPC)
        client_crm -> crm_service "REST"
        client_acl -> acl_service "REST"
        
        # Логика расчета
        client_calc -> calc_service "Запрос расчета (gRPC)"
        calc_service -> tariff_service "Запрос активных правил/коэффициентов"

        # ACL -> External
        acl_service -> ext_repairs "REST"
        acl_service -> ext_fines "REST"
        acl_service -> ext_market_value "REST"
        
        # Notification -> External Providers
        adapter_email -> ext_email "SMTP/API"
        adapter_sms -> ext_sms "SMPP/API"
        adapter_tg -> ext_telegram "HTTPS"
        adapter_push -> ext_push "HTTPS"

        # Data Access
        prop_repo -> db_proposals "SQL"
        crm_service -> db_crm "SQL"
        tariff_service -> db_tariffs "SQL"
        service_facade -> db_read_model "SQL/NoSQL"
        doc_service -> file_storage "S3 API"
        notif_repo -> db_notifications "SQL"

        # Asynchronous (Messaging)
        kafka_prod -> message_broker "Publishes: ProposalCreated"
        
        message_broker -> notif_consumer "Слушает: Отправить уведомление"
        message_broker -> service_facade "Слушает: Обновление витрин"
        message_broker -> tasks_service "Слушает: Требуется ручной разбор"
    }

    # ---------------------------------------------------------------------
    # 5. Views
    # ---------------------------------------------------------------------
    views {
        systemContext insuranceSystem "SystemContext" {
            include *
            autoLayout
        }

        container insuranceSystem "Containers" {
            include *
            autoLayout
        }
        
        component proposals_service "Components_Proposals" {
            include *
            autoLayout
        }
        
        component notification_service "Components_Notifications" {
            include *
            autoLayout
        }

        # --- CODE LEVEL (Level 4) IMAGES ---
        # Здесь мы подключаем ваши внешние диаграммы.
        # Замените пути в поле 'image' на реальные пути к вашим файлам или URL.
        
        image proposals_service "Proposals_Data_ERD" {
            image "https://raw.githubusercontent.com/Readiee/apis-sem-3-c4-model/refs/heads/main/erd-proposals-sem3-apis.png" 
            title "[Code Level] ER-диаграмма Proposals Service"
            description "Схема базы данных db_proposals, включая покрытие и историю решений."
        }

        image notification_service "Notifications_Class_UML" {
            image "https://raw.githubusercontent.com/Readiee/apis-sem-3-c4-model/refs/heads/main/classes-notification-sem3-apis.png"
            title "[Code Level] UML Диаграмма классов Notification Service"
            description "Реализация паттерна Strategy для поддержки многоканальности."
        }

        styles {
            element "Person" {
                shape Person
                background #08427b
                color #ffffff
            }
            element "External System" {
                background #999999
                color #ffffff
            }
            element "Database" {
                shape Cylinder
                color #ffffff
            }
            element "Broker" {
                shape Pipe
                color #ffffff
            }
            element "Web Browser" {
                shape WebBrowser
            }
            element "Mobile App" {
                shape MobileDeviceLandscape
            }
            element "Service" {
                background #1168bd
                color #ffffff
            }
            element "Gateway" {
                shape RoundedBox
                background #555555
                color #ffffff
            }
        }
    }
}