const PAGE_SIZE = 500

type Expense = { date: string; amount: number; memo: string }
type FetchPage = (userId: string, cursor: string | null) => Promise<{ rows: Expense[]; next: string | null }>

function toLine(row: Expense): string {
  return `${row.date},${row.amount},"${row.memo.replaceAll('"', '""')}"\n`
}

export function exportCsv(userId: string, fetchPage: FetchPage): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder()
  let cursor: string | null = null
  return new ReadableStream({
    async pull(controller) {
      try {
        const page = await fetchPage(userId, cursor)
        for (const row of page.rows.slice(0, PAGE_SIZE)) controller.enqueue(encoder.encode(toLine(row)))
        cursor = page.next
        if (cursor === null) controller.close()
      } catch {
        controller.enqueue(encoder.encode('#ERROR\n'))
        controller.close()
      }
    },
  })
}
