# Push Troubleshooting (iOS + Supabase Worker)

## Симптом
- В `notification_queue` у `manual_test_push` видно:
  - `status = sent`
  - `last_error = NULL`
- Но пуш на iPhone не приходит.

## Короткий диагноз
- Backend-цепочка работает (`queue -> worker -> FCM`).
- Чаще всего проблема в токенах устройства:
  - несколько активных iOS-токенов на одном профиле;
  - устаревший токен;
  - токен не обновился после переустановки приложения.

## 1) Проверить последние push-события

```sql
select
  id,
  profile_id,
  channel,
  kind,
  status,
  last_error,
  sent_at,
  created_at
from public.notification_queue
where kind = 'manual_test_push'
  and channel = 'push'
order by created_at desc
limit 10;
```

Ожидаемо: `status = sent`, `last_error = NULL`.

## 2) Проверить токены профиля

```sql
select
  p.email,
  t.platform,
  t.is_active,
  t.updated_at,
  left(t.expo_push_token, 35) || '...' as token
from public.profiles p
join public.profile_push_tokens t on t.profile_id = p.id
where lower(p.email) = lower('freedombkt@gmail.com')
  and lower(coalesce(t.platform, '')) = 'ios'
order by t.updated_at desc;
```

Ожидаемо: ровно 1 активный iOS токен (`is_active = true`).

## 3) Если активных токенов несколько: жесткий сброс

```sql
delete from public.profile_push_tokens t
using public.profiles p
where t.profile_id = p.id
  and lower(p.email) = lower('freedombkt@gmail.com')
  and lower(coalesce(t.platform, '')) = 'ios';
```

После этого:
- открыть приложение на iPhone;
- войти под нужным пользователем;
- подождать 10-15 секунд (токен запишется заново);
- снова выполнить проверку из шага 2.

## 4) Сгенерировать тестовое уведомление с уникальным заголовком

```sql
with me as (
  select p.id as profile_id
  from public.profiles p
  where lower(p.email) = lower('freedombkt@gmail.com')
  limit 1
),
my_hall as (
  select hm.hall_id
  from public.hall_members hm
  join me on me.profile_id = hm.profile_id
  where hm.status = 'approved'
  limit 1
)
insert into public.notification_queue (
  profile_id,
  hall_id,
  tournament_id,
  channel,
  kind,
  title,
  body,
  payload,
  status,
  scheduled_at
)
select
  me.profile_id,
  my_hall.hall_id,
  null::uuid,
  'push',
  'manual_test_push',
  'SQL TEST ' || to_char(now(), 'HH24:MI:SS'),
  'Проверка баннера: ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS'),
  jsonb_build_object('debug_ts', to_char(now(), 'YYYY-MM-DD HH24:MI:SS.MS')),
  'pending',
  now()
from me
cross join my_hall
returning id, title, created_at;
```

## 5) Запустить worker
- Выполнить сохраненный SQL `Send HTTP POST to Notification Worker`.
- Заблокировать экран iPhone перед отправкой.

## 6) Повторная проверка статуса

```sql
select id, title, status, last_error, sent_at, created_at
from public.notification_queue
where kind = 'manual_test_push'
  and channel = 'push'
order by created_at desc
limit 5;
```

## 7) Обязательные условия на iPhone
- Уведомления для приложения включены (`Баннеры`, `Звук`, `Центр уведомлений`).
- `Фокус` выключен.
- Приложение установлено на реальный iPhone (не Simulator).
- Для debug возможны нестабильности; проверка должна быть на release-сборке.

## 8) Постоянный фикс в базе
- Выполнить SQL:
  `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-28-single-active-ios-push-token.sql`
- Он гарантирует:
  - не более одного активного iOS токена на профиль;
  - авто-деактивацию старых iOS токенов при апдейте токена.
