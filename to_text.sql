create or replace function to_text (
   amount numeric,
   currency text,
   scale_mode text default 'text'
) returns text
as $$
/* Выводит денежную сумму прописью(словами).
   Параметры:
      amount - сумма. Не должна превышать 999,999,999,999,999,999,999.99
      currency - валюта. Допустимые значения: 
         рубль  - с дробной частью - копейки 
         доллар - с дробной частью - центы
         тонна  - без дробной части, вместе с scale_mode='none'
      scale_mode - как выводить дробную часть (копейки):
         text - выводить словами. Например: двенадцать копеек
         int  - цифрами. Например: 12 копеек
         none - если дробная часть равна 0, то не выводить вообще,
                если не ноль, то выводить словами
*/
   with
   /* Справочник числительных и валют.
      Все возможные варианты склонений сводятся к формам для трех чисел: 0,1,2
   */
   ref (num, num_m, num_f, cop, cent, rub, dollar,
             num10x3, num10x6, num10x9, num10x12, num10x15, num10x18,
             tonna)
   as (values 
      (0::int, 'ноль'::text, 'ноль'::text, 'копеек'::text, 'центов'::text, 
          'рублей'::text, 'долларов'::text, 'тысяч'::text, 'миллионов'::text, 
          'миллиардов'::text, 'триллионов'::text, 'квадриллионов'::text,
          'квинтиллионов'::text, 'тонн'::text),
      (1::int, 'один'::text, 'одна'::text, 'копейка'::text, 'цент'::text,
          'рубль'::text, 'доллар'::text, 'тысяча'::text, 'миллион'::text,
          'миллиард'::text, 'триллион'::text, 'квадриллион'::text,
          'квинтиллион'::text, 'тонна'::text), 
      (2::int, 'два'::text, 'две'::text, 'копейки'::text, 'цента'::text,
          'рубля'::text, 'доллара'::text, 'тысячи'::text, 'миллиона'::text,
          'миллиарда'::text, 'триллиона'::text, 'квадриллиона'::text,
          'квинтиллиона'::text, 'тонны'::text)
   ),
   /* Некоторые константы */
   const (gender7, gender8, iszero) as (
      select case
                  when to_text.currency = 'рубль'
                  then 'm' -- какого пола рубль
                  when to_text.currency = 'доллар'
                  then 'm' -- какого пола доллар
                  when to_text.currency = 'тонна'
                  then 'f' -- какого пола тонна
             end gender7,
             case
                  when to_text.currency = 'рубль'
                  then 'f' -- пол копейки
                  when to_text.currency = 'доллар'
                  then 'm' -- пол цента
             end gender8,
             trunc(to_text.amount) = 0 as iszero
   ),
   /* Основная идея алгоритма.
      Сумма переводится в строку и разбивается на группы триад.
      Копейки также составляют отдельную триаду (дополняются слева 0).
      Например, сумма 1234.45 превратится в набор триад: 
      000 000 000 000 000 001 234 045
      Дальше каждая триада обрабатывается отдельно, для этого они 
      преобразуются в массив, который разворачивается в строки через unnest.
      В конце, строки с текстами триад сворачиваются в одну через string_agg.
      Для каждой триады нужно превратить число в слова и добавить название.
      Название триады определяется номером (triadnum): 1 - квинтиллионы,
      2 - квадриллионы, 3 - миллиарды и т.д. 
      Последние два номера это валюта и её дробная часть.
      Например если currency='рубль', то triadnum=7 соответствует рублям,
      а 8 - копейкам.
   */
   triads (triadnum, num, int1, int2, int3, int23) as (
      select t.triadnum, 
             t.num, -- три символа триады, для копеек выровнены до 3 знаков 
             substring(t.num,1,1)::int as int1,
             substring(t.num,2,1)::int as int2,
             substring(t.num,3,1)::int as int3,
             substring(t.num,2,2)::int as int23
      from   unnest (string_to_array(
                overlay(ltrim(to_char(
                   to_text.amount,'000,000,000,000,000,000,000.00'
                )) placing ',0' from 28 for 1), ','))
             with ordinality as t(num,triadnum)
      where  /* Пустые триады не нужны, если это не рубли.
                Например в числе 1 000 000р не нужно выводить ничего про тысячи
             */
             t.num <> '000' or t.triadnum = 7 
             /* Если параметр scale_mode не запрещает, то нужны и копейки */
             or (t.triadnum = 8 and to_text.scale_mode <> 'none')
   )
   select string_agg (
          /* Обработка триады */
          case /* Если целая часть суммы равна 0, то можно пропустить
                  всё кроме копеек */ 
               when t.triadnum = 7 and t.num = '000' and const.iszero
               then 'ноль '::text
               /* Вывод дробной части определяется параметром scale_mode */
               when t.triadnum = 8 and to_text.scale_mode = 'text' and 
                    t.num = '000' 
               then 'ноль '::text
               when t.triadnum = 8 and to_text.scale_mode = 'int'
               then substring(t.num,2,2) || ' '::text
          else
             case when t.int1 = 0
                  then ''::text
                  /* сотни */
                  else case t.int1 
                          when 1 then 'сто'::text
                          when 2 then 'двести'::text
                          when 3 then 'триста'::text
                          when 4 then 'четыреста'::text
                          when 5 then 'пятьсот'::text
                          when 6 then 'шестьсот'::text
                          when 7 then 'семьсот'::text
                          when 8 then 'восемьсот'::text
                          when 9 then 'девятьсот'::text
                       end
                  || ' '::text
             end 
             ||
             /* В числах до сотни 11-19 выделяются, пускаем впереди всех */
             case when t.int23 between 11 and 19 
                  then case t.int23
                          when 11 then 'одиннадцать'::text
                          when 12 then 'двенадцать'::text
                          when 13 then 'тринадцать'::text
                          when 14 then 'четырнадцать'::text
                          when 15 then 'пятнадцать'::text
                          when 16 then 'шестнадцать'::text
                          when 17 then 'семнадцать'::text
                          when 18 then 'восемнадцать'::text
                          when 19 then 'девятнадцать'::text
                       end
                       || ' '::text
                  else
                     /* десятки */
                     case when t.int2 between 1 and 9
                     then case t.int2 
                             when 1 then 'десять'::text
                             when 2 then 'двадцать'::text
                             when 3 then 'тридцать'::text
                             when 4 then 'сорок'::text
                             when 5 then 'пятьдесят'::text
                             when 6 then 'шестьдесят'::text
                             when 7 then 'семьдесят'::text
                             when 8 then 'восемьдесят'::text
                             when 9 then 'девяносто'::text
                          end
                          || ' ' ::text
                     else ''::text -- 0 десятков
                     end 
                     ||
                     /* единицы */
                     case when (t.int3 between 1 and 9)
                     then
                        /* Как выводить 1,2: один,два или одна,две?
                           Для триад с 1 по 6 - всегда одинаково.
                           А для 7 и 8 это зависит от пола валюты 
                           (например, рубли - мужской, копейка - женский и т.д.
                        */
                        case when t.int3 in (1,2)
                             then (select case when t.triadnum = 7 and 
                                                    const.gender7 = 'm'::text
                                               then r.num_m
                                               when t.triadnum = 7 and 
                                                    const.gender7 = 'f'::text
                                               then r.num_f
                                               when t.triadnum = 8 and 
                                                    const.gender8 = 'm'::text
                                               then r.num_m
                                               when t.triadnum = 8 and 
                                                    const.gender8 = 'f'::text
                                               then r.num_f
                                          end
                                   from   ref r 
                                   where  r.num = t.int3
                                  )
                             when t.int3 = 3 then 'три'::text
                             when t.int3 = 4 then 'четыре'::text
                             when t.int3 = 5 then 'пять'::text
                             when t.int3 = 6 then 'шесть'::text
                             when t.int3 = 7 then 'семь'::text
                             when t.int3 = 8 then 'восемь'::text
                             when t.int3 = 9 then 'девять'::text
                        end
                        || ' '::text
                     else ''::text -- пустая триада (000)
                     end
             end 
          end
          ||
          /* Названия триад: тысячи, миллионы, и т.д. 
             и названия валют: рубли, копейки, пр.
             Здесь же нужно привязать дробную часть к валюте:
             у рублей - копейки, у долларов - центы.
          */
          (select case when t.triadnum = 8 and to_text.currency = 'рубль'::text
                       then r.cop
                       when t.triadnum = 8 and to_text.currency = 'доллар'::text
                       then r.cent
                       when t.triadnum = 7 and to_text.currency = 'рубль'::text
                       then r.rub
                       when t.triadnum = 7 and to_text.currency = 'доллар'::text
                       then r.dollar
                       when t.triadnum = 7 and to_text.currency = 'тонна'::text
                       then r.tonna
                       when t.triadnum = 6 then r.num10x3
                       when t.triadnum = 5 then r.num10x6
                       when t.triadnum = 4 then r.num10x9
                       when t.triadnum = 3 then r.num10x12
                       when t.triadnum = 2 then r.num10x15
                       when t.triadnum = 1 then r.num10x18
                  end
           from   ref r
           where  r.num = 
                  case when t.int23 between 11 and 19 or
                            t.int3 in (0,5,6,7,8,9)
                       then 0
                       when t.int3 = 1
                       then 1
                       when t.int3 in (2,3,4)
                       then 2
                  end
          )
        , ' '::text) as retval
   from triads t, const;
$$ immutable language sql;

