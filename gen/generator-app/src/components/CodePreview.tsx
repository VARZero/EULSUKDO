import React, { useState } from 'react';
import { rtlSources } from '../utils/rtlGenerator';

interface CodePreviewProps {
  code: string;
  onDownloadProject: () => void;
  downloadEnabled: boolean;
}

export const CodePreview: React.FC<CodePreviewProps> = ({ code, onDownloadProject, downloadEnabled }) => {
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
          <button className="btn btn-primary" onClick={onDownloadProject} disabled={!code || !downloadEnabled}>
            Download Project
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
