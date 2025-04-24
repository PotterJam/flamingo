function WordDisplay({ word = '', blanks = '', length = 0 }) {
	return (
		<div className="text-2xl lg:text-3xl font-semibold tracking-widest text-center p-2 rounded bg-gray-200 min-h-[3rem] flex items-center justify-center select-none">
			{word ? (
				<span>{word}</span>
			) : blanks ? (
				<>
					<span className="mr-2">{blanks}</span>
					<span className="text-sm text-gray-600">({length} letters)</span>
				</>
			) : (
				<span className="text-gray-400">&nbsp;</span>
			)}
		</div>
	);
}

export default WordDisplay;
