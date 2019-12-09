\set ON_ERROR_ROLLBACK ON
begin;

\i to_text.sql

\echo 0
select to_text(0, 'рубль');

\echo scale_mode='text'
select '0.'||c.c::text amount,
       to_text(('0.'||lpad(c.c::text,2,'0'))::numeric, 'рубль') 
       as to_text
from generate_series(0,31) as c(c);

\echo scale_mode='int'
select '1.'||c.c::text amount,
       to_text(('0.'||lpad(c.c::text,2,'0'))::numeric, 
               'доллар', 
               scale_mode => 'int') 
       as to_text
from generate_series(0,31) as c(c);

\echo currency='тонна' и scale_mode='none'
select c.c::text amount,
       to_text(c.c, 
               'тонна', 
               scale_mode => 'none') 
       as to_text
from generate_series(0,31) as c(c);

\echo Максимальный размер, пропуски триад
select t.a as amount, to_text(t.a::numeric, 'доллар')
from   (values 
          ('123456789012345678901.53'),
          ('120000000008901.53')
       ) as t(a);

\echo Евро
select r.r::text||'.'||lpad(c.c::text,2,'0') as amount,
       to_text((r.r::text||'.'||lpad(c.c::text,2,'0'))::numeric, 'евро') 
       as to_text
from generate_series(0,2) as r(r),generate_series(0,2) as c(c);

\echo uom2text - правильные вызовы:
select uom2text(123, 'т');
select uom2text(123, 'ТОННА', 'upper');
select to_text(1234.23, 'рубль', scale_mode => 'int');

\echo uom2text - неверные вызовы:
select uom2text(123, 'т', 'qwe');
select uom2text(123, 'qwe');
select uom2text(-1, 'тонна');
rollback;
