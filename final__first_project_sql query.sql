use finance;
# 1. Billing and collection overview: total billed, collected, outstanding, collection rate, monthly billing vs collections.

   # Total_billed_________________________________________________.
   
   select round(sum(total_amount),2) as Total_Billed from invoices ;
    
    # collected__________________________________________________.
    
       select round(sum(amount_paid),2)  as Collected from payments ;
    
    # Outstanding_________________________________________________.
    
	select round(sum(i.total_amount) - sum(i.adjustment_amount)-
    (select sum(p.amount_paid) from payments p
    join invoices i2 on i2.invoice_id = p.invoice_id 
    where i2.invoice_status <> "Written Off"),2) as outstanding
     from invoices i
    where i.invoice_status <> "Written Off" ;
    
    
## colllection_rate____________________________________________.
    
 select round((select sum(amount_paid) from payments)*100/
 nullif((select sum(total_amount) from invoices
 where invoice_status <> 'written off'),0),2) as 
 collection_rate ;
 
 
 ## monthly billing vs collections________________________________.
 
  with billed as(
select date_format(invoice_date, '%Y-%m') as month, 
sum(total_amount) as billed from invoices
group by date_format(invoice_date, '%Y-%m')
),
collected as (
select date_format(payment_date, '%Y-%m') as month,
sum(amount_paid) as collected from payments
 group by date_format(payment_date, '%Y-%m')
 ),
 month as (
 select month from billed
 union
 select month from collected
 )
 select m.month,
 coalesce(b.billed, 0) as billed,
 coalesce(c.collected,0) as collected,
 round(coalesce(c.collected,0)* 100/nullif(b.billed,0),2)
 as collection_rate_pct from month m
 left join billed b on b.month = m.month
 left join collected c on c.month = m.month
 order by m.month ;
 
 ### ____________________________________________________________________-
 # Q2. Aging report: outstanding balance in buckets Not due, 1-30, 31-60, 61-90, 91-180, 180+ days.
 
 with open_items as (
 select i.invoice_id,
 i.total_amount- coalesce(p.paid, 0) as balance,
 datediff(curdate(), i.due_date) as days_overdue from
 invoices i 
 left join (select invoice_id, sum(amount_paid) as paid
 from payments
 group by invoice_id) p 
 on p.invoice_id = i.invoice_id
 where i.invoice_status<>'written off'
 )
 select case
        when days_overdue<=0       then '1. Not due'
        when days_overdue<=30      then '2. 1-30'
        when days_overdue <=60     then '3. 31-60'
        when days_overdue <= 180   then '5. 91-180'
        else                            '6. 180+'    
   end as aging_bucket,
   count(*)                as invoices,
   round(sum(balance),2)   as outstanding
from open_items
where balance > 0
group by aging_bucket
order by aging_bucket ;


## 3. Days Sales Outstanding (DSO) overall and by segment, industry and region.
### outstanding balance = total billed - paid amount 
###DSO = (Accounts Receivable ÷ Total Credit Sales) × Number of Days in the Period

## DSO by segment, industry and region(one result)


with inv as
(select i.invoice_id, i.customer_id, i.invoice_date, i.total_amount,
i.total_amount - i.adjustment_amount - coalesce(p.paid, 0) as balance
from invoices i
left join (select invoice_id, sum(amount_paid) as paid
from payments
group by invoice_id) p on p.invoice_id = i.invoice_id
where i.invoice_status<>'written off'
)
select round(sum(balance)/nullif(sum(total_amount),0)
* (datediff('2026-10-31', min(invoice_date)) +1), +1 ) as dso_days
from inv ;



## DSO by segment, industry and region(one result)

with inv as (
select i.invoice_id, i.customer_id, i.invoice_date, i.total_amount,
       i.total_amount - i.adjustment_amount -  coalesce(p.paid,0) as balance
from invoices i
left join (select invoice_id, sum(amount_paid) as paid
        from payments
        group by invoice_id) p on p.invoice_id = i.invoice_id
where i.invoice_status<> 'written off'
), 
period as (
     select datediff('2026-10-31', min(invoice_date)) + 1 as days_in_period
     from inv
     ),
detail as (
    select c.segment, c.industry, c.region, inv.total_amount, inv.balance
    from inv	
    join customers c on c.customer_id = inv.customer_id
)
select 'Segment' as dimension, segment as value,
       round(sum(balance)/ nullif(sum(total_amount),0) * (select days_in_period from period),1) as dso_days
       from detail group by segment
union all 
select 'Industry', industry,
       round(sum(balance)/nullif(sum(total_amount),0) *(select days_in_period from period), 1)
from detail group by industry
union all
select 'Region', region,
     round(sum(balance)/ nullif(sum(total_amount), 0) * (select days_in_period from period),1)
from detail group by region
order by dimension, dso_days desc ;

## 4.On-time payment rate and average days late by segment, industry and customer.

with inv_pay as (
  select i.invoice_id, i.customer_id, i.due_date, i.total_amount,
       coalesce(sum(p.amount_paid),0) as paid,
       max(p.payment_date)   as last_payment_date
from invoices i
left join payments p on p.invoice_id = i.invoice_id
where i.invoice_status <> 'written off'
group by i.invoice_id, i.customer_id, i.due_date, i.total_amount
),
paid_inv as (
  select customer_id, 
           datediff(last_payment_date, due_date) as days_late
from inv_pay
where paid>= total_amount
),
detail as (
        select c.customer_id, c.segment, c.industry, pi.days_late
        from paid_inv pi
        join customers c on c.customer_id = pi.customer_id 
)
select 'segment' as dimension, segment as value,
        count(*) as paid_invoices,
        round(100*sum(days_late <=0) / count(*) , 2) as on_time_rate_pct,
        round(avg(case when days_late > 0 then days_late end),1) as avg_days_late
from detail group by segment
union all
select 'Industry', industry,
       count(*),
       round(100*sum(days_late <= 0)/count(*), 2),
       round(avg(case when days_late >0 then days_late end ), 1)
from detail group by industry
union all 
select 'customer', cast(customer_id as char),
        count(*),
        round(100* sum(days_late <=0)/count(*), 2),
        round(avg(case when days_late >0 then days_late end), 1)
from detail
group by customer_id
order by dimension, on_time_rate_pct asc ;   

## Q5. Customer risk ranking: overdue amount, how late they usually pay, disputes, credit limit usage.

with inv as (
	select i.invoice_id, i.customer_id, i.due_date, i.total_amount,
           coalesce(p.paid, 0) as paid,
           p.last_payment_date
	from invoices i
    left join (select invoice_id,
                      sum(amount_paid) as paid,
                      max(payment_date) as last_payment_date
			  from payments
              group by invoice_id) p
              on p.invoice_id = i.invoice_id
	where i.invoice_status<> 'written off'
),
open_bal as (                                                                                            -- 1 and 4: overdue amount, outstanding balance
        select customer_id,
               sum(total_amount - paid) as outstanding,
               sum(case when due_date < curdate() then total_amount - paid else 0 end) as overdue_amount
         from inv
         where total_amount - paid > 0
         group by customer_id
),
pay_behavior as (                                                                                        -- 2: how late they usually pay
       select customer_id,
          avg(greatest(datediff(last_payment_date, due_date),0 )) as avg_days_late
	   from inv
       where paid >= total_amount
       group by customer_id
),
base as (
     select c.customer_id, c.customer_name, c.credit_limit,
            coalesce(o.outstanding, 0) as outstanding,
            coalesce(o.overdue_amount,0)  as overdue_amount,
            round(coalesce(pb.avg_days_late,0),1) as avg_days_late,
            round(coalesce(o.outstanding,0) * 100 / nullif(c.credit_limit,0),1) as credit_usage_pct
      from customers c
      left join open_bal  o on  o.customer_id = c.customer_id
      left join pay_behavior pb on pb.customer_id = c.customer_id
      ),

scored as (
       select *, 
             percent_rank() over(order by overdue_amount)                      as pr_overdue,
             percent_rank() over (order by avg_days_late)                      as pr_late,
             percent_rank() over (order by coalesce(credit_usage_pct,0))       as pr_credit  
      from base
),
final as (
	select *, 
         round(100*(0.40 * pr_overdue + 0.25 * pr_late
                   + 0.20 * pr_credit),1) as risk_score
    from scored
  )
  select rank() over (order by risk_score desc) as risk_rank,
		 customer_id, customer_name,
         overdue_amount, avg_days_late, credit_usage_pct, risk_score,
         case when risk_score >= 70 then 'High'
               when risk_score >= 40 then 'Medium'
               else 'Low' end as risk_tier
from final
order by risk_score desc ;

## 6. Disputes: how many, which reasons, how much value, how much longer disputed invoices take to pay .

select c.customer_name, dispute_flag, coalesce(i.dispute_reason, 'No recorded')   as  reason, 
	   count(*)                                    as  disputed_invoices,
       round(sum(i.total_amount), 2)               as  disputed_value,
       round(sum(i.total_amount - coalesce(p.paid, 0)), 2 )  as still_outstanding 
       from invoices i
left join (select invoice_id, sum(amount_paid) as paid
          from payments
          group by invoice_id ) p on p.invoice_id = i.invoice_id
left join (select * from customers ) c  on i.customer_id = c.customer_id 
where i.dispute_flag = 'yes'  -- or : i.dispute_flag = 1
group by coalesce(i.dispute_reason, 'No recorded'), c.customer_name
order by disputed_invoices desc ;


### 7.Short-payments: invoices where the customer paid less than billed; adjusted vs unexplained.

with inv as (
	 select i.invoice_id, i.customer_id, i.due_date, i.total_amount,
            p.paid, p.last_payment_date
	from invoices i
    join ( select invoice_id,
				  sum(amount_paid) as paid,
                  max(payment_date) as last_payment_date
		   from payments
           group by invoice_id) p on p.invoice_id = i.invoice_id
	where i.invoice_status <>'written off'
    and p.paid < i.total_amount   -- paid less than billed
    
    
),
adj as (
    select invoice_id, sum(adjustment_amount) as adjusted
    from invoices
    group by invoice_id
),
shorts as (
      select inv.invoice_id, inv.customer_id, inv.due_date, inv.total_amount, inv.paid,
              inv.total_amount - inv.paid              as shortfall ,
              coalesce(a.adjusted, 0)                  as adjusted_amount,
              inv.total_amount - inv.paid  - coalesce(a.adjusted, 0 ) as unexplained_amount
	from inv
    left join adj a on a.invoice_id = inv.invoice_id 
)
select *, 
        case when unexplained_amount <= 0 then 'Adjusted (fully explained)'
             when adjusted_amount   > 0 then   'Partly adjusted'
             else                              'Unexplaind' end as short_pay_type
from shorts
order by unexplained_amount desc ;	


## 8. Collections priority list: the top 20 customers or invoices the team should call first, and why.

with inv as (
     select i.invoice_id, i.customer_id, i.due_date, i.total_amount,
            coalesce(p.paid, 0) as paid,
            p.last_payment_date,
            i.total_amount - coalesce(p.paid, 0) as balance
	from invoices i
    left join (select invoice_id, sum(amount_paid) as paid, max(payment_date) as last_payment_date from payments
              group by invoice_id) p on p.invoice_id = i.invoice_id
	where i.invoice_status <> 'written off' 
),
overdue as (
   select customer_id, 
		  sum(balance)            as overdue_amount,
          count(*)                as overdue_invoices,
          max(datediff(curdate(), due_date ))  as oldest_days_overdue   from inv 
                       where balance > 0 and due_date < curdate()
                       group by customer_id 
),
outstanding as (
            select customer_id, sum(balance) as outstanding
            from inv
            where balance > 0
            group by customer_id
), 
history as (
         select customer_id,
                avg(greatest(datediff(last_payment_date, due_date),0)) as avg_days_late from inv
	where paid >= total_amount
    group by customer_id
),
open_disputes as (
select i.customer_id, count(distinct d.invoice_id) as disputed_invoices  from invoices d
join invoices i on i.invoice_id = d.invoice_id
where d.invoice_status <> 'resolved'
group by i.customer_id
),
base as (
      select c.customer_id, c.customer_name,
      o.overdue_amount, o.overdue_invoices, o.oldest_days_overdue,
      round(coalesce(h.avg_days_late,0),1) as avg_days_late,
      coalesce(dp.disputed_invoices, 0)   as disputed_invoices,
      round(os.outstanding * 100 / nullif(c.credit_limit, 0),1) as credit_usage_pct
      from overdue o
      join customers c  on c.customer_id = o.customer_id
      left join outstanding os on os.customer_id = o.customer_id
      left join history h on h.customer_id = o.customer_id
      left join open_disputes dp on dp.customer_id = o.customer_id 
),

scored as (
       select *, 
             round(100 * (0.50 * percent_rank() over(order by overdue_amount)
                          + 0.25 * percent_rank() over(order by oldest_days_overdue)
                          + 0.15 * percent_rank() over(order by avg_days_late)
                          + 0.10 * percent_rank() over (order by coalesce(credit_usage_pct,0))),1) as priority_score 
                          from base 
	)
select row_number() over(order by priority_score desc) as call_order,
       customer_id, customer_name,
       overdue_amount, overdue_invoices, oldest_days_overdue,
       avg_days_late, credit_usage_pct, priority_score,
       case when disputed_invoices > 0 then 'Resolve dispute first, then ask for payment'
			when oldest_days_overdue > 90 then 'Escalate  (senior call / hold new orders)'
            when avg_days_late > 15   then 'Firm reminder, get a payment date'
            else                           'Standard reminder call ' end as suggested_action, 
            concat_ws(';',
            concat('Overdue', format(overdue_amount, 0), 'across',overdue_invoices, 'invoice(s)'),
            concat('oldest is ' , oldest_days_overdue, 'days late'),
            case when avg_days_late > 15 then concat ('usually pays', avg_days_late,'days late') end ,
            case when credit_usage_pct >= 90 then concat('using', credit_usage_pct, '% of credit limit') end ,
            case when disputed_invoices > 0 then concat(disputed_invoices, 'open dispute(s)') end 
            ) as why
from scored
order by priority_score desc
limit 20 ;



# 9. Write-offs: amount, age at write-off, what they had in common .

### Amount and age at write-off__________________________________.

with wo as (
     select i.invoice_id, i.customer_id, i.invoice_date, i.due_date,
            i.total_amount - coalesce(p.paid, 0)   as written_off_amount, 
            p.last_payment_date , 
            datediff('2026-10-31', i.due_date)       as days_past_due_now,
            datediff('2026-10-31', i.invoice_date)   as invoice_age_now
	from  invoices i
    left join(select invoice_id, 
                   sum(amount_paid) as paid,
                   max(payment_date) as last_payment_date
			  from payments
              group by invoice_id) p on p.invoice_id = i.invoice_id
	where i.invoice_status = 'Written Off'
)
select count(*)                          as invoices_written_off,
       round(sum(written_off_amount),2)  as total_written_off,
       round(avg(written_off_amount),2)  as avg_per_invoice,
       round(max(written_off_amount), 2) as largest,
       round(avg(days_past_due_now), 1)  as avg_days_past_due_now,
       round(avg(invoice_age_now), 1)    as avg_invoice_age_now,
       sum(last_payment_date is null)    as never_paid_anything,
       round(avg(datediff(last_payment_date, due_date)),1 )   as avg_days_to_last_payment 
       from wo ;
        


#  What they had in common____________________________________________ 
### Compare the write-off rate in each group. A group that has far more write-offs than its share of billing is a pattern.

with inv as (
       select i.invoice_id, i.customer_id, i.total_amount, 
              coalesce(p.paid,0) as paid,
              (i.invoice_status = 'written off') as is_wo
	   from invoices i
       left join( select invoice_id, sum(amount_paid) as paid
                 from payments
                 group by invoice_id) p on p.invoice_id = i.invoice_id 
),
detail as (
       select c.segment, c.industry, c.region, inv.*
       from inv
       join customers c on c.customer_id = inv.customer_id  
)

select 'Overall' as dimension, 'ALL'  as value,
         count(*) as invoices, sum(is_wo) as written_off,
         round(100 * sum(is_wo) / count(*), 2) as wo_invoice_rate_pct,
         round(100 * sum(case when is_wo then total_amount - paid else 0 end)
			  / nullif(sum(total_amount), 0), 2) as wo_value_rate_pct 
from detail
union all
select 'Segment', segment, count(*), sum(is_wo),
        round(100 * sum(is_wo) / count(*), 2),
        round(100 * sum(case when is_wo then total_amount - paid else 0 end ) / nullif(sum(total_amount),0),2)
from detail group by segment
union all
select 'Industry', industry, count(*), sum(is_wo),
       round(100* sum(is_wo) / count(*), 2),
       round(100 * sum(case when is_wo then total_amount - paid else 0 end) / nullif(sum(total_amount), 0), 2)
from detail group by industry
union all
select 'Region', region, count(*), sum(is_wo),
        round(100 * sum(is_wo)/ count(*), 2 ),
        round(100 * sum(case when is_wo then total_amount - paid else 0 end)/ nullif(sum(total_amount), 0), 2)
from detail group by region 
order by dimension, wo_value_rate_pct desc ;


;
