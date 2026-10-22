import { createFileRoute } from '@tanstack/react-router'

const pageTitle = '유니코드 페이지 제목 🎉 — 아주 긴 한글 문자열 값입니다'
export const Route = createFileRoute('/unicode')({
  component: UnicodePage,
})

const docs = `예시-문서 텍스트 조각: createFileRoute('/fake')( )`

function UnicodePage() {
  return <div>{pageTitle} {docs}</div>
}
