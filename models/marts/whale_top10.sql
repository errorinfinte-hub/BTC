WITH BASE AS (
    select *
    from {{ ref('whale_alert') }}
    order by total_sent desc
    limit 20
)

select *
from BASE