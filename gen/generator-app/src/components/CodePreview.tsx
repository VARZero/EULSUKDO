import React, { useState } from 'react';
import { rtlSources } from '../utils/rtlGenerator';

interface CodePreviewProps {
  code: string;
}

export const CodePreview: React.FC<CodePreviewProps> = ({ code }) => {
  const [copied, setCopied] = useState(false);
  const [fileName, setFileName] = useState('eulsukdo_example_top.sv');
  const preview = fileName === 'eulsukdo_example_top.sv' ? code : rtlSources[fileName];

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(preview);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy code: ', err);
    }
  };

  const handleDownload = () => {
    const blob = new Blob([preview], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="panel code-panel">
      <div className="panel-header">
        <h2 className="panel-title">Gen SystemVerilog</h2>
        <select aria-label="RTL file" value={fileName} onChange={e => setFileName(e.target.value)}>
          <option value="eulsukdo_example_top.sv">Generated wrapper</option>
          {Object.keys(rtlSources).map(name => <option key={name} value={name}>{name}</option>)}
        </select>
        <div className="button-group">
          <button className="btn" onClick={handleCopy} disabled={!preview}>
            {copied ? 'Copied!' : 'Copy Code'}
          </button>
          <button className="btn btn-primary" onClick={handleDownload} disabled={!preview}>
            Download SV
          </button>
        </div>
      </div>
      <div className="code-container">
        <pre className="code-pre">
          {preview}
        </pre>
      </div>
    </div>
  );
};
