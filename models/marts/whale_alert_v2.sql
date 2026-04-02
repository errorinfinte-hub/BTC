WITH WHALES AS (

    select
        output_address,
        sum(output_value) as total_sent,
        count(*) as tx_count
    from {{ ref('stg_btc_transactions') }}
    where output_value > 10
    group by output_address
    order by total_sent desc
)

select
    '{{ invocation_id }}' as invocation_id,
    w.output_address,
    w.total_sent,
    w.tx_count
from WHALES w
order by total_sent desc
